module Rooftop
  module SpektrixSync
    class PriceListSync

      def initialize
        @spektrix_price_lists = Spektrix::Tickets::PriceList.all.to_a
        @rooftop_price_lists = Rooftop::Events::PriceList.all.to_a
        @rooftop_price_bands = Rooftop::Events::PriceBand.all.to_a
        @rooftop_ticket_types = Rooftop::Events::TicketType.all.to_a
      end

      def run
        @spektrix_price_lists.each do |list|
          # find or create a price list
          rooftop_price_list = @rooftop_price_lists.find {|l| l.title == list.id.to_s} || Rooftop::Events::PriceList.new(title: list.id)

          # save the price list to rooftop
          rooftop_price_list.save

          # get an array of known prices
          rooftop_prices = rooftop_price_list.prices.to_a

          # iterate over each spektrix price which looks like this:
          #  => #<Spektrix::Tickets::Price band=nil, is_band_default="true", price="32.00", ticket_type=#<Spektrix::Tickets::Type(ticket-types/201) name="Standard" id="201">>
          list.prices.each do |price|
            # skip ones without a band
            next if price.band.nil?

            # Find the ticket type - we need the id in a sec
            rooftop_ticket_type = @rooftop_ticket_types.find {|t| t.title == price.ticket_type.name}
            rooftop_price = rooftop_prices.find {|p| }

          end
        end
      end

      private



    end
  end
end