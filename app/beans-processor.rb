require 'rubygems'
require 'beanstalk-client'

module Beanstalker
  class NoJobFound < Exception; end

  class BeansProcessor 
    PULLING_TIMER = 0.5

    def self.bslog(message)
      puts "| Processor: \t#{message}"
    end

    # temp tube is used for job browsing and reading purposes
    @@connection = nil
    @@t = {}
    @@states = ["ready", "buried"]
    @@jobs = {"ready" => {}, "buried" => {}}


    # MUST call before any other
    # args: valid, active beanstalk-client connection
    def self.setHandler(connection, options)
      @@connection = connection
    end

    def self.is_connected?
      return !@@connection.nil?
    end

    # returns a hash that contains all
    # information of a given job
    def self.parseJob(job)
      bslog "Parsing job and storing into hash['#{@@current_state}']"
      @@t["jobs"]["#{@@current_state}"]["#{job.id}"] = job.stats
    end

    # returns a hash of all jobs in current tube
    def self.parseTube(tube)
      bslog "Parsing tube `#{tube}'"

      raise NotConnected if !is_connected?

      # make sure we're only modifying current tube
      @@connection.use(tube)
      @@connection.watch(tube)
      tubes = @@connection.list_tubes
      tubes["#{@@connection.last_conn.addr}"].each { |t| @@connection.ignore(t) unless t == tube }
      bslog "Connected at tube `#{@@connection.list_tube_used}'"

      @@t ||= {} # our temp tube

      # initiate our hash
      @@t = { "jobs" =>
              { "reserved" => {}, 
                "urgent" => {}, 
                "ready" => {},
                "buried" => {},
                "delayed" => {}
              },
              "watching" => 0,
              "using" => 0,
              "waiting" => 0}
      
      #data = @@connection.stats_tube(tube)

      @@current_state = "ready"
      while true
        # retrieve
          job = popJob(@@connection)

        break if job.nil? # no more jobs in queue
        
        # process
          parseJob(job)
          pushJob(job)
      end
      
      # restore original queue
      rebuildTube(tube)
      return @@t
    end

    def self.pushJob(job)
      bslog "Pushing job into #{@@connection.list_tube_used} with id #{job.id}"
      @@jobs["#{@@current_state}"]["#{job.id}"] = job unless @@jobs["#{@@current_state}"].has_key?("#{job.id}")
    end

    # gets job from front of queue
    def self.popJob(connection)
      bslog "Popping job from #{connection.list_tube_used}"
      connection.reserve(PULLING_TIMER) rescue nil
    end

    def self.rebuildTube(tube)
      @@connection.watch(tube)
      @@connection.use(tube)

      return if @@jobs["#{@@current_state}"].empty?
      @@jobs["#{@@current_state}"].each do |id, j|
        j.release
      end

      # clear up
      for state in @@states do
        @@jobs["#{state}"].clear
      end
    end

    def self.buryJob(id)
      return if !is_connected?

      bslog "Burying job with id #{id}"
      job = getJob(id)
      job.bury

    end

    def self.releaseJob(id)
      return if !is_connected?

      job = getJob(id)
      job.release

    end

    # helper method for fetching Jobs using ID
    def self.getJob(id)
      @@connection.peek_job(id).fetch("#{@@connection.last_conn.addr}")
    end

  end
end
