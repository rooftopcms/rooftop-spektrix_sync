module Rooftop
  module SpektrixSync
    class InstanceSync

      def initialize(spektrix_instance, event_sync)
        @spektrix_instance_statuses = event_sync.spektrix_instance_statuses
        @spektrix_event = event_sync.spektrix_event
        @rooftop_event = event_sync.rooftop_event
        @logger = event_sync.logger
        @spektrix_instance = spektrix_instance
        @rooftop_instance = find_rooftop_instance_by_spektrix_id(@spektrix_instance.id) || @rooftop_event.instances.build(status: nil, meta_attributes: {})
        @rooftop_price_lists = event_sync.rooftop_price_lists
      end

      def sync
        # This is a bit of a hack: we have to create a new instance and assign all the attributes from the old one, so it has an _event_id param.
        if @rooftop_instance.persisted?
          @rooftop_instance = @rooftop_event.instances.build(@rooftop_instance.attributes)
          instance_updated = true
        end
        update_price
        if @rooftop_instance.price_list_id.nil?
          @logger.warn("No price list for Spektrix instance id #{@spektrix_instance.id}")
          return
        end
        update_meta_attributes
        update_availability
        update_on_sale

        if event_instance_requires_sync?
          @rooftop_instance.meta_attributes[:spektrix_hash] = generate_spektrix_hash(@spektrix_instance)

          if @rooftop_instance.save!
            @logger.debug("#{instance_updated ? "Updated" : "Created"} Rooftop instance #{@rooftop_instance.id}")
            return @rooftop_instance.id
          end
        else
          @logger.debug("Skipping event instance save")
          return nil
        end
      end

      private
      def event_instance_requires_sync?
        rooftop_event_instance_hash = @rooftop_instance.meta_attributes['spektrix_hash']

        @rooftop_instance.id.nil? || !rooftop_event_instance_hash || rooftop_event_instance_hash != generate_spektrix_hash(@spektrix_instance)
      end

      def generate_spektrix_hash(event_instance)
        Digest::MD5.hexdigest(event_instance.attributes.to_s)
      end

      def find_rooftop_instance_by_spektrix_id(spektrix_id)
        @rooftop_event.instances.to_a.find {|i| i.meta_attributes[:spektrix_id] == spektrix_id }
      end

      def update_price
        @rooftop_instance.price_list_id = @rooftop_price_lists.find {|l| l.meta_attributes[:spektrix_id].to_i == @spektrix_instance.price_list_id}.try(:id)
      end

      def update_meta_attributes
        @rooftop_instance.meta_attributes = @spektrix_instance.custom_attributes.merge(spektrix_id: @spektrix_instance.id, spektrix_hash: @rooftop_instance.meta_attributes.try(:[], :spektrix_hash))
      end

      def update_on_sale
        # TODO: there is a bug in the Rooftop events plugin which means that instances which are draft won't be shown
        # as assigned to the event. Because it's a nested resource, there's no real risk to publishing
        # the instance immediately.
        # if SpektrixSync.configuration.present? && SpektrixSync.configuration[:on_sale_if_new_event]
        #   @rooftop_instance.status = @spektrix_instance.is_on_sale ? 'publish' : 'draft'
        # else
        #   @rooftop_instance.status ||= "draft"
        # end
        # @rooftop_instance.status = "publish"
        
        @rooftop_instance.status = @spektrix_instance.is_on_sale=="true" ? 'publish' : 'draft'
      end

      def update_availability
        instance_status = @spektrix_instance_statuses.find{|is| is.instance[:id] == @spektrix_instance.id} || @spektrix_instance.status

        availability = {
          availability: {
            starts_at: @spektrix_instance.start.iso8601,
            stops_at: @spektrix_instance.start.advance(seconds: @rooftop_event.meta_attributes[:duration]),
            seats_capacity: instance_status.capacity,
            seats_available: instance_status.available
          }
        }
        @rooftop_instance.title = @rooftop_event.title + ": " + @spektrix_instance.start.strftime("%d %b %Y %H:%M")
        @rooftop_instance.meta_attributes.merge!(availability)
      end


    end
  end
end
