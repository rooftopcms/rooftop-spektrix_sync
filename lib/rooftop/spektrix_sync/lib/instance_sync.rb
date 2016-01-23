module Rooftop
  module SpektrixSync
    class InstanceSync

      def initialize(spektrix_instance, event_sync)
        @spektrix_event = event_sync.spektrix_event
        @rooftop_event = event_sync.rooftop_event
        @logger = event_sync.logger
        @spektrix_instance = spektrix_instance
        @rooftop_instance = find_rooftop_instance_by_spektrix_id(@spektrix_instance.id) || @rooftop_event.instances.build(status: nil)
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
        if @rooftop_instance.save!
          @logger.debug("#{instance_updated ? "Updated" : "Created"} Rooftop instance #{@rooftop_instance.id}")
        end
      end

      private
      def find_rooftop_instance_by_spektrix_id(spektrix_id)
        @rooftop_event.instances.to_a.find {|i| i.meta_attributes[:spektrix_id] == spektrix_id }
      end

      def update_price
        @rooftop_instance.price_list_id = @rooftop_price_lists.find {|l| l.meta_attributes[:spektrix_id].to_i == @spektrix_instance.price_list_id}.try(:id)
      end

      def update_meta_attributes
        @rooftop_instance.meta_attributes = @spektrix_instance.custom_attributes.merge(spektrix_id: @spektrix_instance.id)
      end

      def update_on_sale
        if SpektrixSync.configuration.present? && SpektrixSync.configuration[:on_sale_if_new_event]
          @rooftop_instance.status = @spektrix_instance.is_on_sale ? 'publish' : 'draft'
        else
          @rooftop_instance.status ||= "draft"
        end
      end

      def update_availability
        availability = {
          availability: {
            starts_at: @spektrix_instance.start.iso8601,
            stops_at: @spektrix_instance.start.advance(seconds: @rooftop_event.meta_attributes[:duration]),
            seats_capacity: @spektrix_instance.status.capacity,
            seats_available: @spektrix_instance.status.available
          }
        }
        @rooftop_instance.meta_attributes.merge!(availability)
      end


    end
  end
end