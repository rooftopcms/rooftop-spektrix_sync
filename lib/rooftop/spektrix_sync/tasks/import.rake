namespace :rooftop do
  namespace :spektrix do

    task :prepare, [:since, :logger_path] do |task, args|
      logger_path = args[:logger_path] || STDOUT
      Rooftop::SpektrixSync.logger = Logger.new(logger_path, 'daily')
      @since = eval(args[:since]) rescue DateTime.now
    end


    desc "Synchronise events from Spektrix to Rooftop"
    task :sync_events, [:since, :logger_path]  => [:environment, :prepare] do |task, args|
      Rooftop::SpektrixSync::SyncTask.run_events_import(@since)
    end

    desc "Synchronise events and prices from Spektrix to Rooftop"
    task :sync_all, [:since, :logger_path]  => [:environment, :prepare] do |task, args|
      Rooftop::SpektrixSync::SyncTask.run_full_import(@since)
    end

    desc "Synchronise events and prices from Spektrix to Rooftop"
    task :sync_prices, [:since, :logger_path]  => [:environment, :prepare] do |task, args|
      Rooftop::SpektrixSync::SyncTask.run_prices_import(@since)
    end

    desc "Sync specific event"
    task :sync_event, [:spektrix_event_id, :since, :logger_path] => [:environment, :prepare] do |task, args|
      Rooftop::SpektrixSync::SyncTask.run_events_import(@since, args[:spektrix_event_id])
    end


  end
end
