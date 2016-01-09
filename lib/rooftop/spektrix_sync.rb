require 'active_support'

require "rooftop/spektrix_sync/version"
require 'require_all'
require_rel 'spektrix_sync/lib'

module Rooftop
  module SpektrixSync

    if defined?(::Rails)
      require 'rooftop/spektrix_sync/railtie'
    end


  end
end
