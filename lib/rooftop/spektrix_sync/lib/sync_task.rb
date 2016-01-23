module Rooftop
  module SpektrixSync
    class SyncTask
      attr_accessor :starting_at, :logger, :error_file
      attr_reader :spektrix_events,
                  :rooftop_events,
                  :spektrix_price_lists,
                  :rooftop_price_lists,
                  :rooftop_ticket_types,
                  :rooftop_price_bands

      def initialize(starting_at)
        begin
          Rooftop.preview = true
          @starting_at = starting_at || DateTime.now
          @logger = SpektrixSync.logger || Logger.new(STDOUT)
          fetch_event_data
        rescue => e
          @logger.error("Couldn't start sync: #{e}")
        end

      end

      def fetch_event_data
        @logger.debug("Fetching all Spektrix events")
        @spektrix_events = @spektrix_events.present? ? @spektrix_events : Spektrix::Events::Event.all(instance_start_from: @starting_at.iso8601).to_a
        @logger.debug("Fetching all Rooftop events")
        @rooftop_events = @rooftop_events.present? ? @rooftop_events : Rooftop::Events::Event.all.to_a
        @logger.debug("Fetching all Spektrix price lists")
        @spektrix_price_lists = @spektrix_price_lists.present? ? @spektrix_price_lists : Spektrix::Tickets::PriceList.all.to_a
        @logger.debug("Fetching all Rooftop Price lists")
        @rooftop_price_lists = @rooftop_price_lists.present? ? @rooftop_price_lists : Rooftop::Events::PriceList.all.to_a
        @logger.debug("Fetching all Rooftop ticket types")
        @rooftop_ticket_types = @rooftop_ticket_types.present? ? @rooftop_ticket_types : Rooftop::Events::TicketType.all.to_a
        @logger.debug("Fetching all Rooftop price bands")
        @rooftop_price_bands = @rooftop_price_bands.present? ? @rooftop_price_bands : Rooftop::Events::PriceBand.all.to_a
      end



      def self.run(starting_at=nil)
        self.new(starting_at).run
      end

      def run
        begin
          create_or_update_price_bands
          fetch_event_data
          create_or_update_ticket_types
          fetch_event_data
          create_or_update_prices
          fetch_event_data
          create_or_update_events
          fetch_event_data
          delete_orphan_spektrix_events
        rescue => e
          @logger.error(e)
        end

      end

      private

      def create_or_update_events
        begin
          @spektrix_events.each_with_index do |event, i|
            @logger.debug("Sync #{i+1} / #{@spektrix_events.length}: #{event.title}")
            item = EventSync.new(event, self)
            item.sync_to_rooftop
          end
          delete_orphan_spektrix_events
        rescue => e
          @logger.error(e.to_s)
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
            @logger.debug("Removed Rooftop event #{title} which doesn't exist in Spektrix")
          end
        end
      end

      def create_or_update_price_bands
        begin
          rooftop_bands = Rooftop::Events::PriceBand.all.to_a
          spektrix_bands = Spektrix::Tickets::Band.all.to_a
          # create or update existing
          spektrix_bands.each do |band|
            @logger.debug("Updating band #{band.name}")
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
          @logger.error(e.to_s)
        end
      end

      def create_or_update_ticket_types
        begin
          rooftop_ticket_types = Rooftop::Events::TicketType.all.to_a
          spektrix_ticket_types = Spektrix::Tickets::Type.all.to_a
          # create or update exiting
          spektrix_ticket_types.each do |type|
            @logger.debug("Updating ticket type #{type.name}")
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
          @logger.error(e.to_s)
        end
      end

      def create_or_update_prices
        if @rooftop_price_lists.empty?
          p = 1
        end

        PriceListSync.new(self).run
      end
    end
  end
end