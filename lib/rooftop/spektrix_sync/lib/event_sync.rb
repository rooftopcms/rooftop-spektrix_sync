module Rooftop
  module SpektrixSync
    class EventSync
      attr_reader :spektrix_event,
                  :spektrix_instance_statuses,
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

        @logger.debug("Fetching all instance statuses for event")
        @spektrix_instance_statuses = Spektrix::Events::InstanceStatus.where(event_id: @spektrix_event.id, all: true).to_a
      end

      def sync_to_rooftop
        begin
          # find the event
          @rooftop_event ||= Rooftop::Events::Event.new({
            title: @spektrix_event.title,
            content: {basic: {content: @spektrix_event.description}},
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

        sync_event_instances = true

        if event_requires_sync?
          @rooftop_event.meta_attributes[:spektrix_hash] = generate_spektrix_hash(@spektrix_event)

          if @rooftop_event.save!
            @logger.debug("Saved event: #{@rooftop_event.title} #{@rooftop_event.id}")
          else
            sync_event_instances = false
          end
        else
          @logger.debug("Skipping event update")
        end

        sync_instances if sync_event_instances
      end

      private
      def event_requires_sync?
        rooftop_event_hash = @rooftop_event.meta_attributes['spektrix_hash']

        @rooftop_event.id.nil? || !rooftop_event_hash || rooftop_event_hash != generate_spektrix_hash(@spektrix_event)
      end

      def generate_spektrix_hash(event)
        Digest::MD5.hexdigest(event.attributes.to_s)
      end

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
          @rooftop_event.status ||= "draft"
        end
      end

      def sync_instances
        @rooftop_instances = @rooftop_event.instances.to_a
        @spektrix_instances = @spektrix_event.instances.to_a

        synced_to_rooftop = [] # array of event instance id's that were updated/created on RT
        @spektrix_instances.each_with_index do |instance, i|
          begin
            tries ||= 2
            instance_sync = Rooftop::SpektrixSync::InstanceSync.new(instance, self)
            synced_to_rooftop << instance_sync.sync
          rescue
            retry unless (tries -= 1 ).zero?
          end
        end

        # if we have any updated event instances, send the POST /events/$event-instance/update_metadata request
        # to trigger the event meta data update on Rooftop (sets first/last event instance dates on an event to aid in filtering and sorting)
        if synced_to_rooftop.compact.any?
          update_event_metadata
        end
      end

      def update_event_metadata
        @logger.debug("Saved event instances. Updating event metadata")
        Rooftop::Events::Event.post("#{@rooftop_event.class.collection_path}/#{@rooftop_event.id}/update_metadata")
      end
    end
  end
end
