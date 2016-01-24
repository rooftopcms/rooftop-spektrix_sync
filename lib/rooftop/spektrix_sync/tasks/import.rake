namespace :rooftop do
  namespace :spektrix do

    task :prepare, [:since] do |task, args|
      Rooftop::SpektrixSync.logger = Logger.new(STDOUT)
      since = eval(args[:since]) rescue DateTime.now
      @sync = Rooftop::SpektrixSync::SyncTask
    end


    desc "Synchronise events from Spektrix to Rooftop"
    task :sync_events, [:since]  => [:environment, :prepare] do |task, args|
      @sync.run_events_import
    end

    desc "Synchronise events and prices from Spektrix to Rooftop"
    task :sync_all, [:since]  => [:environment, :prepare] do |task, args|
      @sync.run_full_import
    end

    desc "Synchronise events and prices from Spektrix to Rooftop"
    task :sync_prices, [:since]  => [:environment, :prepare] do |task, args|
      @sync.run_prices_import
    end


  end
end
