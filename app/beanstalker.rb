# beanstalker.rb

require 'rubygems'
require 'sinatra/base'
#require 'sinatra'
require '../Client/lib/beanstalk-client'
require 'erb'
#require 'sass'
require 'app/beans-processor'

module Beanstalker

  class CouldNotSetup < Exception; end
  class CouldNotConnect < Exception; end
  class NotConnected < Exception; end

  class Server < Sinatra::Base

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
      # disable server runing on object creation .. has to be manually called
      disable :run
      enable :logging, :sessions

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
        BeansProcessor::setHandler(@@bsh, @@config['beanstalkd'])
      rescue Exception => e 
        raise CouldNotConnect, "Could not connect to beanstalkd @ #{@@config['beanstalkd']['host']}:#{@@config['beanstalkd']['port']}.\n`#{e.message}'"
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
        "<a href='#{ROOT}'>#{body}</a>"
      end

      def appRoot
        ROOT
      end

      def printHeader
        "Beanstalkd @ #{@@config['beanstalkd']['host']}:#{@@config['beanstalkd']['port']}"
      end

      def versioned_stylesheet(stylesheet)
        #puts "Getting stylesheet #{stylesheet}.."
        #"/stylesheets/#{stylesheet}.css?" + File.mtime(File.join(Sinatra::Application.views, "stylesheets", "#{stylesheet}.css")).to_i.to_s
        "/stylesheets/#{stylesheet}.css"
      end

      def versioned_javascript(js)
        #puts "Getting js ..."
        #"/javascripts/#{js}.js?" + File.mtime(File.join(Sinatra::Application.public, "javascripts", "#{js}.js")).to_i.to_s
        "/javascripts/#{js}.js"
      end

      #def pullJob
      #  job = @@bsh.reserve(2)
      #end

      def pushJob(message, options = {})
        priority = options[:priority] || 65536
        delay    = options[:delay] || 0
        ttr      = options[:ttr] || 120

        @@bsh.put(message, priority, delay, ttr)
      end

    end # end of helpers

    before do
      halt "Connection is not setup!" unless is_setup?
      @@bsh.watch(@@current_tube) unless @@current_tube.nil?
      @@bsh.use(@@current_tube) unless @@current_tube.nil?
    end

    get '/' do
      @stats = @@bsh.stats
      erb :index
    end

    get '/tubes' do
      @tubes = @@bsh.list_tubes[@@bsh.last_server]
      erb :"tubes/index", :locals => {:bsh => @@bsh }
    end

    get '/tubes/:tube_name' do |name|
      #@tube = @@bsh.stats_tube(name)
      @@current_tube = name
      
      tube_info = BeansProcessor::parseTube(@@current_tube)
      erb :"tubes/show", :locals => { :info => tube_info }
    end

    get '/jobs/:id' do

    end

    get '/jobs/:id/bury' do |id|
      BeansProcessor::buryJob(id)
      tube_name = @@bsh.peek_job(id).fetch("#{@@bsh.last_conn.addr}").stats["tube"]
      #bslog "Redirecting to tube #{tube_name}"
      redirect "#{appRoot}/tubes/#{tube_name}"
    end

    get '/tube/:id/kick/:nr' do |id, nr|

    end

    get '/stylesheets/application.css' do
      content_type 'text/css'
      sass :"/stylesheets/application"
    end
  end

end
