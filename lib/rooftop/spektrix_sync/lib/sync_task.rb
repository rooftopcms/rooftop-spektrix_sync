module Rooftop
  module SpektrixSync
    class SyncTask
      attr_accessor :starting_at
      attr_reader :spektrix_events, :rooftop_events

      def initialize(starting_at: DateTime.now)
        @starting_at = starting_at
        @spektrix_events = Spektrix::Events::Event.all(instance_start_from: @starting_at.iso8601).to_a
        @rooftop_events = Rooftop::Events::Event.all(per_page: 9999999).to_a
      end

      def find_event(event)
        @rooftop_events.find {|e| e.event_meta[:custom_attributes][:spektrix_id].to_i == event.id.to_i}
      end

      def update_event(event)
        e = find_event(event)
        e = update_custom_attributes(event,e)
        e = update_on_sale(event,e)
        if e.save
          puts "Updated #{e.title}".green
        end
      end

      def update_custom_attributes(spektrix_event, rooftop_event)
        rooftop_event.event_meta = {
          custom_attributes: {
            spektrix_id: spektrix_event.id
          }
        }
        spektrix_event.custom_attributes.each do |key, value|
          rooftop_event.event_meta[:custom_attributes][key] = value
        end
        return rooftop_event
      end

      def update_on_sale(spektrix_event, rooftop_event)
        case spektrix_event.is_on_sale
          when true
            rooftop_event.status = 'publish'
          else
            rooftop_event.status = 'draft'
        end
        return rooftop_event
      end

      def create_event(event)
        e = Rooftop::Events::Event.new({
                                         title: event.title,
                                         content: {basic: {content: event.description}},
                                       })
        e = update_custom_attributes(event, e)
        e = update_on_sale(event,e)
        if e.save
          puts "Created #{event.title}".yellow
        end
      end

      def run
        # Create or update events
        @spektrix_events.each do |event|
          if find_event(event)
            update_event(event)
          else
            create_event(event)
          end
        end

        #remove events which don't exist in spektrix


      end
    end
  end
end