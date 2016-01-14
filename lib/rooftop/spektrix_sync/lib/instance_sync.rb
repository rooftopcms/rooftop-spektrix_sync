module Rooftop
  module SpektrixSync
    class InstanceSync

      def initialize(spektrix_instance, event_sync)
        @spektrix_event = event_sync.spektrix_event
        @rooftop_event = event_sync.rooftop_event
        @logger = event_sync.logger
        @spektrix_instance = spektrix_instance
        @rooftop_instance = find_rooftop_instance_by_spektrix_id(@spektrix_instance.id) || @rooftop_event.instances.build
      end

      def sync
        # This is a bit of a hack: we have to create a new instance and assign all the attributes from the old one, so it has an _event_id param.
        unless @rooftop_instance.new?
          @rooftop_instance = @rooftop_event.instances.build(@rooftop_instance.attributes)
          instance_updated = true
        end
        update_meta_attributes
        update_availability
        update_on_sale
        if @rooftop_instance.save!
          @logger.debug("#{instance_updated ? "Updated" : "Created"} instance #{@rooftop_instance.id}")
        end
      end

      private
      def find_rooftop_instance_by_spektrix_id(spektrix_id)
        @rooftop_event.instances.to_a.find {|i| i.meta_attributes[:spektrix_id] == spektrix_id }
      end

      def update_meta_attributes
        @rooftop_instance.meta_attributes = @spektrix_instance.custom_attributes.merge(spektrix_id: @spektrix_instance.id)
      end

      def update_on_sale
        @rooftop_instance.status = @spektrix_instance.is_on_sale ? "publish" : "draft"
      end

      def update_availability
        @spektrix_instance_status = @spektrix_instance.status
        availability = {
          availability: {
            starts_at: @spektrix_instance.start.iso8601,
            stops_at: @spektrix_instance.start.advance(seconds: @rooftop_event.meta_attributes[:duration]),
            seats_capacity: @spektrix_instance_status.capacity,
            seats_available: @spektrix_instance_status.available
          }
        }
        @rooftop_instance.meta_attributes.merge!(availability)
      end


    end
  end
end