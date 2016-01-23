module Rooftop
  module SpektrixSync
    class EventSync
      attr_reader :spektrix_event,
                  :rooftop_event,
                  :rooftop_price_lists,
                  :logger

      def initialize(spektrix_event, sync_task)
        @rooftop_events = sync_task.rooftop_events
        @spektrix_events = sync_task.spektrix_events
        @logger = sync_task.logger
        @spektrix_event = spektrix_event
        @rooftop_event = @rooftop_events.find {|e| e.meta_attributes[:spektrix_id].try(:to_i) == @spektrix_event.id.to_i}
        @rooftop_price_lists = sync_task.rooftop_price_lists
      end

      def sync_to_rooftop
        begin
          # find the event
          @rooftop_event ||= Rooftop::Events::Event.new({
            title: @spektrix_event.title,
            content: {basic: {content: @spektrix_event.description}},
            meta_attributes: {}
          })
          sync()
        rescue => e
          @logger.error(e.to_s)
        end
      end

      def sync
        update_meta_attributes
        update_on_sale
        if @rooftop_event.save!
          @logger.debug("Saved event: #{@rooftop_event.title} #{@rooftop_event.id}")
          sync_instances
        end
      end

      private
      def update_meta_attributes
        @rooftop_event.meta_attributes ||= {}
        @rooftop_event.meta_attributes[:spektrix_id] = @spektrix_event.id
        @spektrix_event.custom_attributes.each do |key, value|
          @rooftop_event.meta_attributes[key] = value
        end
        @rooftop_event.meta_attributes[:duration] = @spektrix_event.duration.to_i
      end

      def update_on_sale
        if Spektrix.configuration.present? && Spektrix.configuration[:on_sale_if_new_event]
          @rooftop_event.status = @spektrix_event.is_on_sale ? 'publish' : 'draft'
        else
          @rooftop_event.status ||= "draft"
        end
      end

      def sync_instances
        @rooftop_instances = @rooftop_event.instances.to_a
        @spektrix_instances = @spektrix_event.instances.to_a
        @spektrix_instances.each_with_index do |instance, i|
          instance_sync = Rooftop::SpektrixSync::InstanceSync.new(instance, self)
          instance_sync.sync
        end

        update_event_metadata
      end

      def update_event_metadata
        @logger.debug("Saved event instances. Updating event metadata")
        Rooftop::Events::Event.post("#{@rooftop_event.class.collection_path}/#{@rooftop_event.id}/update_metadata")
      end
    end
  end
end
