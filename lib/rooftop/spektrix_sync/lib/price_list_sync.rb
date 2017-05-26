module Rooftop
  module SpektrixSync
    class PriceListSync

      def initialize(sync_task)
        @spektrix_price_lists = sync_task.spektrix_price_lists
        @rooftop_price_lists = sync_task.rooftop_price_lists
        @rooftop_ticket_types = sync_task.rooftop_ticket_types
        @rooftop_price_bands = sync_task.rooftop_price_bands
        @logger = sync_task.logger
      end

      def run
        sync_price_lists
        # Todo we need to put this in a rake task instead of running every time.
        # remove_orphan_price_lists
      end

      private

      def sync_price_lists
        # begin
          @spektrix_price_lists.each do |spektrix_price_list|
            # Don't bother syncing a price list where none of the prices have bands.
            if spektrix_price_list.prices.nil?
              @logger.error("[spektrix] Spektrix price list ID #{spektrix_price_list.id} has no prices at all")
              next
            end
            if spektrix_price_list.prices.select {|p| !p.band.nil?}.empty?
              @logger.error("[spektrix] Spektrix price list ID #{spektrix_price_list.id} has prices with missing bands.")
            end

            # find or create a price list
            @rooftop_price_list = @rooftop_price_lists.find {|l| l.meta_attributes[:spektrix_id] == spektrix_price_list.id.to_s} || Rooftop::Events::PriceList.new(title: spektrix_price_list.id, meta_attributes: {})
            @rooftop_price_list.meta_attributes[:spektrix_id] = spektrix_price_list.id

            new_price_list = @rooftop_price_list.new?
            # save the price list to rooftop
            if @rooftop_price_list.save!
              @logger.info("[spektrix] #{new_price_list ? "Created" : "Updated"} price list #{spektrix_price_list.id}")
              sync_prices(spektrix_price_list, @rooftop_price_list)
            end
          end
        # rescue => e
        #   @logger.error(e.to_s)
        # end
      end

      def sync_prices(spektrix_price_list, rooftop_price_list)
        # begin
          spektrix_price_list.prices.each_with_index do |spektrix_price, i |
            @logger.info("[spektrix] syncing price #{i+1} / #{spektrix_price_list.prices.count}")
            # skip ones without a band
            if spektrix_price.band.nil?
              @logger.error("[spektrix] Spektrix price list ID: #{spektrix_price_list.id}: Price #{spektrix_price.price} with ticket type #{spektrix_price.ticket_type.name} does not have a band")
              next
            end
            current_rooftop_price = find_rooftop_price(rooftop_price_list, spektrix_price)
            # because updating a price is hard with a nested resource, we'll destroy and recreate with the same settings
            new_price = rooftop_price_list.prices.build
            if current_rooftop_price
              new_price.assign_attributes(current_rooftop_price.attributes)
            end

            ticket_type_id = find_rooftop_ticket_type(spektrix_price).try(:id)
            price_band_id = find_rooftop_price_band(spektrix_price).try(:id)
            if ticket_type_id.nil?
              @logger.error("[spektrix] Ticket type for spektrix price #{spektrix_price.price} with ticket type #{spektrix_price.ticket_type.name} is nil")
              next
            end

            if price_band_id.nil?
              @logger.error("[spektrix] Price band for spektrix price #{spektrix_price.price} with ticket type #{spektrix_price.ticket_type.name} is nil")
              next
            end

            new_price.meta_attributes = {
              is_band_default: (spektrix_price.is_band_default == "true"),
              ticket_type_id: ticket_type_id,
              price_band_id: price_band_id,
              ticket_price: spektrix_price.price.to_f
            }

            new_price.title = "#{spektrix_price.band.name} (£#{new_price.meta_attributes[:ticket_price]})"
            if new_price.save!
              @logger.error("[spektrix] Spektrix price list ID: #{spektrix_price_list.id}: Saved price £#{new_price.meta_attributes[:ticket_price]} with ticket type #{spektrix_price.ticket_type.name} for price band #{spektrix_price.band.name}")
            end
          end
        # rescue => e
        #   @logger.error(e.to_s)
        # end
      end

      def remove_orphan_price_lists
        begin
          rooftop_spektrix_ids = @rooftop_price_lists.collect {|l| l.meta_attributes[:spektrix_id].to_i}
          spektrix_ids = @spektrix_price_lists.collect {|l| l.id.to_i}
          spektrix_ids_to_remove = (rooftop_spektrix_ids - (rooftop_spektrix_ids & spektrix_ids))
          rooftop_ids_to_remove = spektrix_ids_to_remove.collect do |spektrix_id|
            @rooftop_price_lists.find {|l| l.meta_attributes[:spektrix_id].to_i == spektrix_id}.id
          end
          Rooftop::Events::PriceList.where(post__in: rooftop_ids_to_remove).each do |pricelist|
            if pricelist.destroy
              @logger.info("[spektrix] Removed rooftop price list #{id} which didn't exist in spektrix")
            end
          end
        rescue => e
          @logger.fatal("[spektrix] #{e}")
        end
      end

      def find_rooftop_price(rooftop_price_list,spektrix_price)
        rooftop_price_list.prices.to_a.find {|p| p.meta_attributes[:spektrix_id] == spektrix_price.id}
      end

      def find_rooftop_ticket_type(spektrix_price)
        @rooftop_ticket_types.find {|t| CGI::unescapeHTML(t.title.gsub(/&#8211\;/, '-')) == CGI::unescapeHTML(spektrix_price.ticket_type.name)}
      end

      def find_rooftop_price_band(spektrix_price)
        @rooftop_price_bands.find {|b| CGI::unescapeHTML(b.title.gsub(/&#8211\;/, '-')) == CGI::unescapeHTML(spektrix_price.band.name)}
      end

    end
  end
end
