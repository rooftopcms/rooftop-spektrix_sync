require "rooftop/spektrix_sync/version"

module Rooftop
  module SpektrixSync

    if defined?(::Rails)
      require 'rooftop/spektrix_sync/railtie'

    end

  end
end
