module Rooftop
  module SpektrixSync
    class SyncTask
      attr_accessor :starting_at
      attr_reader :spektrix_events, :rooftop_events

      def initialize(starting_at: DateTime.now)
        @starting_at = starting_at
        @spektrix_events = Spektrix::Events::Event.all(instance_start_from: @starting_at.iso8601)
      end

      def run
        @spektrix_events.each do |event|
          puts event.title
        end
      end
    end
  end
end