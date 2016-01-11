module Rooftop
  module SpektrixSync
    class SyncItem
      def initialize(spektrix_event, sync_task)
        @rooftop_events = sync_task.rooftop_events
        @spektrix_events = sync_task.spektrix_events
        @spektrix_event = spektrix_event
        @spektrix_instances = @spektrix_event.instances
        @rooftop_event = @rooftop_events.find {|e| e.meta_attributes[:spektrix_id].to_i == @spektrix_event.id.to_i}
      end

      def sync_to_rooftop
        begin
          # find the event
          if @rooftop_event
            #we need to be updating
            update()
          else
            create()
            #we need to be creating
          end
        rescue => e
          puts e.to_s.red
        end
      end

      def update
        update_meta_attributes
        update_on_sale
        if @rooftop_event.save!
          puts "Updated #{@rooftop_event.title}".green
        end
      end

      def create
        @rooftop_event = Rooftop::Events::Event.new({
                                         title: @spektrix_event.title,
                                         content: {basic: {content: @spektrix_event.description}},
                                         meta_attributes: {}
                                       })
        update_meta_attributes
        update_on_sale

        # save the event, and add instances
        if @rooftop_event.save!
          update_instances
        end
      end

      private
      def update_meta_attributes
        @rooftop_event.meta_attributes[:spektrix_id] = @spektrix_event.id
        @spektrix_event.custom_attributes.each do |key, value|
          @rooftop_event.meta_attributes[key] = value
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

      def update_instances

      end
    end
  end
end