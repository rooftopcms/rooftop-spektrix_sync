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
        @spektrix_events.each do |event|
          item = SyncItem.new(event, self)
          item.sync_to_rooftop
        end


      end
    end
  end
end