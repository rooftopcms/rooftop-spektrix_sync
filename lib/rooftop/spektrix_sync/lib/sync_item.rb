module Rooftop
  module SpektrixSync
    class SyncItem
      def initialize(spektrix_event, sync_task)
        @rooftop_events = sync_task.rooftop_events
        @spektrix_events = sync_task.spektrix_events
        @spektrix_event = spektrix_event
        @rooftop_event = @rooftop_events.find {|e| e.custom_attributes[:spektrix_id].to_i == @spektrix_event.id.to_i}
      end

      def sync_to_rooftop
        # find the event
        if @rooftop_event
          #we need to be updating
          update()
        else
          create()
          #we need to be creating
        end





        # mop up any which don't exist in spek but do exist in RT
      end

      def update
        update_custom_attributes
        update_on_sale
        if @rooftop_event.save!
          puts "Updated #{@rooftop_event.title}".green
        else
          puts "Something went wrong saving #{@rooftop_event}".red
        end

      end

      def create
        @rooftop_event = Rooftop::Events::Event.new({
                                         title: @spektrix_event.title,
                                         content: {basic: {content: @spektrix_event.description}},
                                       })
        update_custom_attributes
        update_on_sale
        if @rooftop_event.save
          puts "Created #{@rooftop_event.title}".yellow
        end
      end

      private
      def update_custom_attributes
        @rooftop_event.event_meta = {
          custom_attributes: {
            spektrix_id: @spektrix_event.id
          }
        }
        @spektrix_event.custom_attributes.each do |key, value|
          @rooftop_event.event_meta[:custom_attributes][key] = value
        end
      end

      def update_on_sale
        case @spektrix_event.is_on_sale
          when true
            @rooftop_event.status = 'publish'
          else
            @rooftop_event.status = 'draft'
        end
      end
    end
  end
end