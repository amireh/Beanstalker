namespace :beanstalker do

  desc "Starts Beanstalker web server"
  task :start do
    require 'app/beanstalker.rb'
    puts "Running Beanstalker front-end server..."
    Beanstalker::Server.run!
  end

end
