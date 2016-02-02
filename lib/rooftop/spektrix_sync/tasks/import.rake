namespace :rooftop do
  namespace :spektrix do

    task :prepare, [:since] do |task, args|
      Rooftop::SpektrixSync.logger = Logger.new('/var/log/rooftop-spektrix-import.log', 'daily')
      @since = eval(args[:since]) rescue DateTime.now
    end


    desc "Synchronise events from Spektrix to Rooftop"
    task :sync_events, [:since]  => [:environment, :prepare] do |task, args|
      Rooftop::SpektrixSync::SyncTask.run_events_import(@since)
    end

    desc "Synchronise events and prices from Spektrix to Rooftop"
    task :sync_all, [:since]  => [:environment, :prepare] do |task, args|
      Rooftop::SpektrixSync::SyncTask.run_full_import(@since)
    end

    desc "Synchronise events and prices from Spektrix to Rooftop"
    task :sync_prices, [:since]  => [:environment, :prepare] do |task, args|
      Rooftop::SpektrixSync::SyncTask.run_prices_import(@since)
    end


  end
end
