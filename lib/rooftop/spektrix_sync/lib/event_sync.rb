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
        @sync_task = sync_task
        @logger.info("[spektrix]  Fetching all instance statuses for event")
        @spektrix_instance_statuses = Spektrix::Events::InstanceStatus.where(event_id: @spektrix_event.id, all: true).to_a
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
          @logger.fatal("[spektrix] #{e}")
        end
      end

      def sync
        update_meta_attributes
        update_on_sale

        sync_event_instances = true

        if event_requires_sync?
          @rooftop_event.meta_attributes[:spektrix_hash] = generate_spektrix_hash(@spektrix_event)
          rooftop_event_title = @rooftop_event.title

          new_event = !@rooftop_event.persisted?
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
            @logger.info("[spektrix]  #{new_event ? 'Created' : 'Saved'} event: #{rooftop_event_title} #{@rooftop_event.id}")
          else
            sync_event_instances = false
          end
        else
          @logger.info("[spektrix]  Skipping event update")
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
          @rooftop_event.restore_status! #don't send status with the request
        end
      end

      def sync_instances
        @rooftop_instances = @rooftop_event.instances.to_a
        @spektrix_instances = @spektrix_event.instances.to_a
        @logger.info("[spektrix]  Checking #{@rooftop_instances.size} instances..")

        synced_to_rooftop = [] # array of event instance id's that were updated/created on RT

        # delete any RT instances that aren't included in the set of spektrix event instances
        rooftop_instance_spektrix_ids = @rooftop_instances.collect{|i| i.meta_attributes[:spektrix_id]}.compact
        spektrix_instance_ids         = @spektrix_instances.collect(&:id)
        delete_instance_ids           = rooftop_instance_spektrix_ids - spektrix_instance_ids
        delete_instances              = @rooftop_instances.select{|i| delete_instance_ids.include?(i.meta_attributes[:spektrix_id])}
        # before we can call .destroy on an instance, we need to mutate the object so it has an :event_id to hit the proper destroy method endpoint...
        delete_instances.each do |instance|
          @logger.info("[spektrix]  Deleting Rooftop Instance #{instance.id}")
          instance.tap{|i| i.event_id = @rooftop_event.meta_attributes[:spektrix_id]}.destroy
        end

        @spektrix_instances.each_with_index do |instance, i|
          @logger.info("[spektrix] Instance #{instance.id}")
          begin
            tries ||= 2
            instance_sync = Rooftop::SpektrixSync::InstanceSync.new(instance, self)
            synced_to_rooftop << instance_sync.sync
          rescue => e
            if (tries -= 1).zero?
              @logger.fatal("[spektrix] Not retrying... #{e}")
            else
              @logger.warn("[spektrix] Retrying... #{e}")
              retry
            end
          end
        end

        # if we have any updated event instances, send the POST /events/$event-instance/update_metadata request
        # to trigger the event meta data update on Rooftop (sets first/last event instance dates on an event to aid in filtering and sorting)
        if synced_to_rooftop.compact.any?
          update_event_metadata
        end
      end

      def update_event_metadata
        @logger.info("[spektrix] Saved event instances. Updating event metadata")
        Rooftop::Events::Event.post("#{@rooftop_event.class.collection_path}/#{@rooftop_event.id}/update_metadata")
      end
    end
  end
end
