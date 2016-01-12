module Rooftop
  module SpektrixSync
    class SyncTask
      attr_accessor :starting_at, :logger
      attr_reader :spektrix_events, :rooftop_events

      def initialize(starting_at: DateTime.now)
        Rooftop.preview = true
        @starting_at = starting_at
        @spektrix_events = Spektrix::Events::Event.all(instance_start_from: @starting_at.iso8601).to_a
        @rooftop_events = Rooftop::Events::Event.all.to_a
        @logger = Logger.new(STDOUT)
      end

      def run
        create_or_update_price_bands
        create_or_update_ticket_types
        create_or_update_events
        delete_orphan_spektrix_events
      end

      private

      def create_or_update_events
        # begin
          @spektrix_events.each_with_index do |event, i|
            @logger.debug("Sync #{i+1} / #{@spektrix_events.length}: #{event.title}")
            item = EventSync.new(event, self)
            item.sync_to_rooftop
          end
          delete_orphan_spektrix_events
        # rescue => e
        #   @logger.warn(e.to_s)
        # end
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
        rooftop_ids_to_delete.each do |id|
          event_to_delete = Rooftop::Events::Event.find(id)
          if event_to_delete.destroy
            @logger.debug("Removed event #{event_to_delete.title}")
          end
        end
      end

      def create_or_update_price_bands
        rooftop_bands = Rooftop::Events::PriceBand.all.to_a
        Spektrix::Tickets::Band.all.each do |band|
          rooftop_band = rooftop_bands.find {|b| b.title == band.name} || Rooftop::Events::PriceBand.new
          rooftop_band.title = band.name
          rooftop_band.save!
        end
      end

      def create_or_update_ticket_types
        rooftop_ticket_types = Rooftop::Events::TicketType.all.to_a
        Spektrix::Tickets::Type.all.each do |type|
          rooftop_ticket_type = rooftop_ticket_types.find {|t| t.title == type.name} || Rooftop::Events::TicketType.new
          rooftop_ticket_type.title = type.name
          rooftop_ticket_type.save!
        end
      end
    end
  end
end