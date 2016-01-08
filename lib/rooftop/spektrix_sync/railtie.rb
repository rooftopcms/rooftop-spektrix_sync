module Rooftop
  module SpektrixSync
    class Railtie < ::Rails::Railtie

      rake_tasks do
        load "rooftop/spektrix_sync/tasks/import.rake"
      end
    end
  end
end