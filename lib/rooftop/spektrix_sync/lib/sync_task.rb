module Rooftop
  module SpektrixSync
    class SyncTask
      attr_accessor :starting_at, :logger, :error_file
      attr_reader :spektrix_events,
                  :rooftop_events,
                  :spektrix_price_lists,
                  :rooftop_price_lists,
                  :rooftop_ticket_types,
                  :rooftop_price_bands,
                  :options

      PIDFILE = ARGV.find{|a| a=~/pidname=[^$]+/}.try(:split, '=').try(:last) || 'sync'
      PIDPATH = "/tmp/rooftop-spektrix-#{PIDFILE}.pid"

      def initialize(starting_at, opts={})
        if defined?(Rooftop::Rails)
          Rooftop::Rails.configuration.perform_object_caching = false
        end

        begin
          Rooftop.include_drafts = true
          if defined?(Rooftop::Rails)
            Rooftop::Rails.configuration.perform_object_caching = false
          end
          @starting_at = starting_at || DateTime.now
          @logger = SpektrixSync.logger || Logger.new(STDOUT)
          default_opts = {
            import_price_bands: false,
            import_ticket_types: false,
            import_prices: false,
            import_events: true,
            delete_orphan_events: false,
            accept_empty_rooftop_events: false,
            import_spektrix_description: true
          }
          @options = default_opts.merge!(opts)
          @logger.info("[spektrix] Running with options: #{@options.select {|k,v| k if v}.keys.join("[spektrix] , ")}")
        rescue => e
          @logger.fatal("[spektrix] Couldn't start sync: #{e}")
        end
      end

      def fetch_rooftop_and_spektrix_data
        @spektrix_events = @spektrix_events.present? ? @spektrix_events : Spektrix::Events::Event.all(instance_start_from: @starting_at.iso8601).to_a
        if @options[:spektrix_event_id]
          @logger.info("[spektrix] Selecting single Spektrix event")
          @spektrix_events = @spektrix_events.select {|e| e.id == @options[:spektrix_event_id].to_s}
        else
          @logger.info("[spektrix] Fetching all Spektrix events")
        end

        @logger.info("[spektrix] Fetching all Rooftop events")
        @rooftop_events = Rooftop::Events::Event.all.to_a
        unless @options[:accept_empty_rooftop_events]
          @logger.info("[spektrix] No Rooftop events")
          raise StandardError, "Rooftop returned an empty set of events which is probably wrong" if @rooftop_events.empty?
        end
        @logger.info("[spektrix] Fetching all Spektrix price lists")
        @spektrix_price_lists = @spektrix_price_lists.present? ? @spektrix_price_lists : Spektrix::Tickets::PriceList.all.to_a
        @logger.info("[spektrix] Fetching all Rooftop Price lists")
        @rooftop_price_lists = Rooftop::Events::PriceList.all.to_a

        if @options[:import_price_bands] || @options[:import_ticket_types] || @options[:import_prices]
          @logger.info("[spektrix] Fetching all Spektrix price lists")
          @spektrix_price_lists = @spektrix_price_lists.present? ? @spektrix_price_lists : Spektrix::Tickets::PriceList.all.to_a
          @logger.info("[spektrix] Fetching all Rooftop ticket types")
          @rooftop_ticket_types = Rooftop::Events::TicketType.all.to_a
          @logger.info("[spektrix] Fetching all Rooftop price bands")
          @rooftop_price_bands = Rooftop::Events::PriceBand.all.to_a
        end
      end

      def self.run(starting_at=nil, opts={})
        sync_pid = Process.get_pid(Rooftop::SpektrixSync::SyncTask::PIDPATH)

        if sync_pid && Process.exists?(sync_pid.to_i)
          raise 'Rooftop::SpektrixSync::SyncRunning'
        end

        # if we're here, we can create a new pidfile and start the sync
        Process.create_pid(Rooftop::SpektrixSync::SyncTask::PIDPATH)
        self.new(starting_at,opts).run

        # remove the pid
        Process.remove_pidfile(Rooftop::SpektrixSync::SyncTask::PIDPATH)
      end

      def self.run_events_import(starting_at=nil, event_id=nil, opts={})
        opts = event_id.present? ? opts.merge({spektrix_event_id: event_id}) : opts
        self.run(starting_at, opts)
      end

      def self.run_full_import(starting_at=nil, opts={})
        self.run(starting_at, {
          import_price_bands: true,
          import_ticket_types: true,
          import_prices: true,
          import_events: true,
          delete_orphan_events: false
        }.merge(opts))
      end

      def self.run_prices_import(starting_at=nil, opts={})
        self.run(starting_at, {
          import_price_bands: true,
          import_ticket_types: true,
          import_prices: true,
          import_events: false,
          delete_orphan_events: false
        }.merge(opts))
      end


      def run
        begin
          if @options[:import_price_bands]
            fetch_rooftop_and_spektrix_data
            create_or_update_price_bands
          end
          if @options[:import_ticket_types]
            fetch_rooftop_and_spektrix_data
            create_or_update_ticket_types
          end
          if @options[:import_prices]
            fetch_rooftop_and_spektrix_data
            create_or_update_prices
          end
          if @options[:import_events]
            fetch_rooftop_and_spektrix_data
            create_or_update_events
          end
          # TODO: the delete method is over-eager. Resolve the issue.
          # if @options[:delete_orphan_events]
          #   fetch_event_data
          #   delete_orphan_spektrix_events
          # end
        rescue => e
          @logger.fatal("[spektrix] #{e}")
        end

      end

      private

      def create_or_update_events
        begin
          tries ||= 2
          @spektrix_events.each_with_index do |event, i|
            @logger.info("[spektrix] Sync #{i+1} / #{@spektrix_events.length}: #{event.title}")
            item = EventSync.new(event, self)
            item.sync_to_rooftop
          end
        rescue => e
          if (tries -= 1).zero?
            @logger.fatal("[spektrix] Not retrying...#{e.to_s}")
          else
            @logger.error("[spektrix] Retrying...#{e.to_s}")
            retry
          end
        end
      end

      # Mop up any Rooftop events which don't exist in spektrix, if they have spektrix ID
      def delete_orphan_spektrix_events
        @spektrix_event_ids = @spektrix_events.collect {|e| e.id.to_i}
        @rooftop_event_ids = @rooftop_events.inject({}) do |hash, e|
          hash[e.id] = e.meta_attributes[:spektrix_id].to_i
          hash
        end
        @rooftop_event_ids.reject! {|k,v| v == 0} #remove events with no spektrix ID; we don't want to remove them.
        spektrix_ids_to_delete = (@rooftop_event_ids.values - (@rooftop_event_ids.values & @spektrix_event_ids))
        rooftop_ids_to_delete = @rooftop_event_ids.select {|k,v| spektrix_ids_to_delete.include?(v)}.keys
        Rooftop::Events::Event.where(post__in: rooftop_ids_to_delete).each do |rooftop_event|
          title = rooftop_event.title
          if rooftop_event.destroy
            @logger.info("[spektrix] Removed Rooftop event #{title} which doesn't exist in Spektrix")
          end
        end
      end

      def create_or_update_price_bands
        begin
          rooftop_bands = Rooftop::Events::PriceBand.all.to_a
          spektrix_bands = Spektrix::Tickets::Band.all.to_a
          # create or update existing
          spektrix_bands.each do |band|
            @logger.info("[spektrix] Updating band #{band.name}")
            rooftop_band = rooftop_bands.find {|b| b.title == band.name} || Rooftop::Events::PriceBand.new
            rooftop_band.title = band.name
            rooftop_band.save!
          end

          #delete ones on rooftop which aren't in spektrix
          rooftop_titles = rooftop_bands.collect(&:title)
          spektrix_titles = spektrix_bands.collect(&:name)
          (rooftop_titles - (rooftop_titles & spektrix_titles)).each do |title|
            rooftop_bands.find {|b| b.title == title}.destroy
          end
        rescue => e
          @logger.fatal("[spektrix] #{e}")
        end


      end

      def create_or_update_ticket_types
        begin
          rooftop_ticket_types = Rooftop::Events::TicketType.all.to_a
          spektrix_ticket_types = Spektrix::Tickets::Type.all.to_a
          # create or update exiting
          spektrix_ticket_types.each do |type|
            @logger.info("[spektrix] Updating ticket type #{type.name}")
            rooftop_ticket_type = rooftop_ticket_types.find {|t| t.title == type.name} || Rooftop::Events::TicketType.new
            rooftop_ticket_type.title = type.name
            rooftop_ticket_type.save!
          end

          #delete ones on rooftop which aren't in spektrix
          rooftop_titles = rooftop_ticket_types.collect(&:title)
          spektrix_titles = spektrix_ticket_types.collect(&:name)
          (rooftop_titles - (rooftop_titles & spektrix_titles)).each do |title|
            rooftop_ticket_types.find {|b| b.title == title}.destroy
          end
        rescue => e
          @logger.fatal("[spektrix] #{e}")
        end
      end

      # This is where we generate a price list sync instance
      def create_or_update_prices
        PriceListSync.new(self).run
        #In this circumstance, we need to assume some prices have changed, so we'll invalidate the
        # instance variable which contains the collection of prices on both sides. This means that
        # next time fetch_rooftop_and_spektrix_data is called, the latest will be pulled from the APIs.
        @spektrix_price_lists = nil
        @rooftop_price_lists = nil

      end
    end
  end
end
