namespace :rooftop do
  namespace :spektrix do

    task :prepare, [:since] do |task, args|
      SpektrixSync.logger = ::Rails.logger
      since = eval(args[:since]) rescue DateTime.now
      @task = Rooftop::SpektrixSync::SyncTask.new(starting_at: since)
    end


    desc "Synchronise events from Spektrix to Rooftop"
    task :sync, [:since]  => [:environment, :prepare] do |task, args|
      @task.run
    end


  end
end
