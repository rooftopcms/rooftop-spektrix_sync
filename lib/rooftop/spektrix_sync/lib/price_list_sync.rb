module Rooftop
  module SpektrixSync
    class PriceListSync

      def initialize(sync_task)
        @spektrix_price_lists = sync_task.spektrix_price_lists
        @rooftop_price_lists = sync_task.rooftop_price_lists
        @rooftop_ticket_types = sync_task.rooftop_ticket_types
        @rooftop_price_bands = sync_task.rooftop_price_bands
      end

      def run
        sync_price_lists
        remove_orphan_price_lists
      end

      private

      def sync_price_lists
        @spektrix_price_lists.each do |spektrix_price_list|
          # Don't bother syncing a price list where none of the prices have bands.
          if spektrix_price_list.prices.select {|p| !p.band.nil?}.empty?
            puts "Skipping price list #{spektrix_price_list.id}"
            next
          end

          # find or create a price list
          @rooftop_price_list = @rooftop_price_lists.find {|l| l.meta_attributes[:spektrix_id] == spektrix_price_list.id.to_s} || Rooftop::Events::PriceList.new(title: spektrix_price_list.id, meta_attributes: {})
          @rooftop_price_list.meta_attributes[:spektrix_id] = spektrix_price_list.id

          new_price_list = @rooftop_price_list.new?
          # save the price list to rooftop
          if @rooftop_price_list.save!
            puts "#{new_price_list ? "Created" : "Updated"} price list #{spektrix_price_list.id}"
            sync_prices(spektrix_price_list, @rooftop_price_list)
          end
        end
      end

      def sync_prices(spektrix_price_list, rooftop_price_list)
        spektrix_price_list.prices.each_with_index do |spektrix_price, i |
          puts "syncing price #{i+1} / #{spektrix_price_list.prices.count}"
          # skip ones without a band
          if spektrix_price.band.nil?
            puts "skipping #{spektrix_price.name}"
            next
          end
          current_rooftop_price = find_rooftop_price(rooftop_price_list, spektrix_price)
          # because updating a price is hard with a nested resource, we'll destroy and recreate with the same settings
          new_price = rooftop_price_list.prices.build
          if current_rooftop_price
            new_price.assign_attributes(current_rooftop_price.attributes)
          end
          new_price.meta_attributes = {
            is_band_default: (spektrix_price.is_band_default == "true"),
            ticket_type_id: find_rooftop_ticket_type(spektrix_price).id,
            price_band_id: find_rooftop_price_band(spektrix_price).id,
            ticket_price: spektrix_price.price.to_f
          }
          new_price.title = "#{spektrix_price.band.name} (£#{new_price.meta_attributes[:ticket_price]})"
          if new_price.save!
            puts "saved #{new_price.meta_attributes[:ticket_price]}: #{spektrix_price.band.name}"
          end
        end
      end

      def remove_orphan_price_lists
        rooftop_spektrix_ids = @rooftop_price_lists.collect {|l| l.meta_attributes[:spektrix_id].to_i}
        spektrix_ids = @spektrix_price_lists.collect {|l| l.id.to_i}
        spektrix_ids_to_remove = (rooftop_spektrix_ids - (rooftop_spektrix_ids & spektrix_ids))
        rooftop_ids_to_remove = @rooftop_price_lists.select {|l| spektrix_ids_to_remove.include?(l.meta_attributes[:spektrix_id].to_i)}.collect(&:id)
        rooftop_ids_to_remove.each do |id|
          list_to_remove  = Rooftop::Events::PriceList.find(id)
          if list_to_remove.destroy
            puts "removed rooftop price list #{id} which didn't exist in spektrix"
          end
        end
      end

      def find_rooftop_price(rooftop_price_list,spektrix_price)
        rooftop_price_list.prices.to_a.find {|p| p.meta_attributes[:spektrix_id] == spektrix_price.id}
      end

      def find_rooftop_ticket_type(spektrix_price)
        @rooftop_ticket_types.find {|t| t.title == spektrix_price.ticket_type.name}
      end

      def find_rooftop_price_band(spektrix_price)
        @rooftop_price_bands.find {|b| b.title == spektrix_price.band.name}
      end


    end
  end
end