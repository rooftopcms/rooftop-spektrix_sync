module Rooftop
  module SpektrixSync
    class SyncTask
      attr_accessor :starting_at
      attr_reader :spektrix_events, :rooftop_events

      def initialize(starting_at: DateTime.now)
        Rooftop.preview = true
        @starting_at = starting_at
        @spektrix_events = Spektrix::Events::Event.all(instance_start_from: @starting_at.iso8601).to_a
        @rooftop_events = Rooftop::Events::Event.all.to_a
      end

      def run
        # Create or update events
        begin
          @spektrix_events.each do |event|
            item = SyncItem.new(event, self)
            item.sync_to_rooftop
          end

          delete_orphan_spektrix_events
        rescue => e
          puts e.to_s.red
        end

      end

      private

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
            puts "Removed event #{event_to_delete.title}".red
          end
        end
      end
    end
  end
end