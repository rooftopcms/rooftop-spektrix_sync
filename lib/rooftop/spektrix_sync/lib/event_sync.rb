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
        @sync_task = sync_task
      end

      def sync_to_rooftop
        begin
          # find the event
          @rooftop_event ||= Rooftop::Events::Event.new({
            title: @spektrix_event.title,
            content: {
              basic: {
                content: @sync_task.options[:import_spektrix_description] ? @spektrix_event.description : ""
              }
            },
            meta_attributes: {},
            status: nil
          })
          sync()
        rescue => e
          @logger.error(e.to_s)
        end
      end

      def sync
        update_meta_attributes
        update_on_sale
        if @rooftop_event.persisted?
          # Ensure we're not overwriting newer stuff in RT with older stuff from this sync by
          # removing the title and content if this is a PUT request (i.e. it already exists in RT)
          @rooftop_event.restore_title!
          @rooftop_event.restore_content!
          @rooftop_event.restore_slug!
          @rooftop_event.restore_link!
          @rooftop_event.restore_event_instance_availabilities!
        end

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
        if SpektrixSync.configuration.present? && SpektrixSync.configuration[:on_sale_if_new_event]
          @rooftop_event.status = @spektrix_event.is_on_sale ? 'publish' : 'draft'
        else
          @rooftop_event.restore_status! #don't send status with the request
        end
      end

      def sync_instances
        @rooftop_instances = @rooftop_event.instances.to_a
        @spektrix_instances = @spektrix_event.instances.to_a
        @spektrix_instances.each_with_index do |instance, i|
          begin
            tries ||= 2
            instance_sync = Rooftop::SpektrixSync::InstanceSync.new(instance, self)
            instance_sync.sync
          rescue
            retry unless (tries -= 1 ).zero?
          end
        end

        update_event_metadata unless @rooftop_instances.empty?
      end

      def update_event_metadata
        @logger.debug("Saved event instances. Updating event metadata")
        Rooftop::Events::Event.post("#{@rooftop_event.class.collection_path}/#{@rooftop_event.id}/update_metadata")
      end
    end
  end
end
