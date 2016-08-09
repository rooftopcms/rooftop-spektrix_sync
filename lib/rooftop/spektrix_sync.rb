require 'active_support'
require 'colorize'

require "rooftop/spektrix_sync/version"
require 'require_all'
require_rel 'spektrix_sync/lib'

module Rooftop
  module SpektrixSync

    class << self
      attr_accessor :logger, :configuration
    end

    if defined?(::Rails)
      require 'rooftop/spektrix_sync/railtie'
    end

    require 'rooftop/spektrix_sync/process'

  end
end
