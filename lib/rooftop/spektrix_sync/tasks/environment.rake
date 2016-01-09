desc "Set up the environment, if there's no Rails environment"
task :environment do
  Rooftop.configure do |config|
    #todo - figure out how to configure Rooftop for situations
    # where we're running this outside the context of a Rails app
  end
end