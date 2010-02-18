# beanstalker.rb

require 'rubygems'
require 'sinatra/base'
require 'sinatra/content_for'
require '../Client/lib/beanstalk-client'
require 'erb'
require 'rack-flash'
require 'app/beans-processor'

module Beanstalker

  class CouldNotSetup < Exception; end
  class CouldNotConnect < Exception; end
  class NotConnected < Exception; end

  class Server < Sinatra::Base
  
    include Sinatra::ContentFor

    # helper logger
    def self.bslog(message, header=false)
      puts "| ---------- #{message} ----------" if header
      puts "| Server: \t#{message}" if !header
    end

    configure do
      bslog "Configuring app...", true

      set :root, File.join(File.dirname(__FILE__), "..")
      set :views, Proc.new { File.join(root, "views") }
      set :public, Proc.new { File.join(root, "public") }
      set :static, Proc.new { File.join(root, "public") }
      set :environment, :production
      disable :run # disable server runing on object creation .. has to be manually called
      enable :logging, :sessions
      use Rack::Flash # used for flash[:notice]s

      # load our config file
      @@config = YAML.load(File.open(File.join(File.expand_path(File.dirname(__FILE__)), '..', 'config', 'server.yml')))
      if @@config.empty? then
        raise CouldNotSetup, "Could not load config file!"
      end
      set :host, @@config["application"]["host"]
      set :port, @@config["application"]["port"]

      # handler to beanstalkd connection
      @@bsh = nil 
      begin

        # initialise connection
        @@bsh = Beanstalk::Pool.new("#{@@config['beanstalkd']['host']}:#{@@config['beanstalkd']['port']}")

        # initialise our processor
        BeansProcessor::setHandler(@@bsh, @@config['beanstalkd'])
      rescue Exception => e 
        raise (CouldNotConnect, 
              "Could not connect to beanstalkd @ 
              #{@@config['beanstalkd']['host']}:
              #{@@config['beanstalkd']['port']}.
              \nError body: `#{e.message}'")
      end

      ROOT = "http://#{@@config['application']['host']}:#{@@config['application']['port']}"

      @@current_tube = nil

      bslog "Started successfully."
    end # end of configuration block
   
    helpers do
      def is_setup?
        return !@@bsh.nil?
      end
      
      def linkToRoot(body='Back')
        "<a class='link-back' href='#{ROOT}'>#{body}</a>"
      end

      def linkToTubes(body='Back')
        "<a class='link-back' href='#{ROOT}/tubes'>#{body}</a>"
      end

      def appRoot
        ROOT
      end

      def printHeader
        "Beanstalkd @ #{@@config['beanstalkd']['host']}:#{@@config['beanstalkd']['port']}"
      end

      def versioned_stylesheet(stylesheet)
        "/stylesheets/#{stylesheet}.css"
      end

      def versioned_javascript(js)
        "/javascripts/#{js}.js"
      end

    end # end of helpers

    before do
      # validate our connection before processing any request
      halt "Connection is not setup!" unless is_setup?

      # make sure we're using the proper tube
      @@bsh.watch(@@current_tube) unless @@current_tube.nil?
      @@bsh.use(@@current_tube) unless @@current_tube.nil?
    end

    # index
    get '/' do
      @stats = @@bsh.stats
      erb :index
    end

    # lists all tubes
    get '/tubes' do
      @tubes = @@bsh.list_tubes[@@bsh.last_server]
      erb :"tubes/index", :locals => {:bsh => @@bsh }
    end

    # retrieves all jobs attainable within this Tube
    get '/tubes/:tube_name' do
      @@current_tube = params[:tube_name]

      # parse tube and pass it off
      tube_info = BeansProcessor::parseTube(@@current_tube)
      erb :"tubes/show", :locals => { :info => tube_info }
    end

    # deletes job with :id
    get '/jobs/:id/delete' do |id|
      tube = BeansProcessor::getJob(id)["tube"]
      BeansProcessor::deleteJob(id)

      flash[:notice] = "Deleted job with id `#{id}' successfully."
      redirect "/tubes/#{tube}"
    end

    # kicks a specified number of jobs in :tube_name
    post '/tubes/:tube_name/kick' do |tube|
      BeansProcessor::kickTube(params[:nrJobsToKick])

      flash[:notice] = "Kicked #{params[:nrJobsToKick]} jobs in tube `#{tube}'."
      redirect "/tubes/#{tube}"
    end

  end
end
