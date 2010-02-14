require 'rubygems'
require '../Client/lib/beanstalk-client'

module Beanstalker
  class NoJobFound < Exception; end
  class InvalidOperation < Exception; end

  class BeansProcessor 
    PULLING_TIMER = 0.5

    def self.bslog(message)
      puts "| Processor: \t#{message}"
    end

    # temp tube is used for job browsing and reading purposes
    @@pool = nil
    @@connection = nil
    @@t = {}
    @@states = ["reserved", "ready", "buried"]
    @@jobs = {"reserved" => {}, "ready" => {}, "buried" => {}}


    # MUST call before any other
    # args: valid, active beanstalk-client connection
    def self.setHandler(connection, options)
      @@pool = connection
      @@connection = @@pool.last_conn
    end

    def self.is_connected?
      @@connection = @@pool.last_conn
      return !@@pool.nil?
    end

    # returns a hash that contains all
    # information of a given job
    def self.parseJob(idJob)
      raise NotConnected if !is_connected?

      job = @@connection.job_stats(idJob)
      bslog "Parsing job and storing into hash['#{@@current_state}']"
      @@t["jobs"]["#{job["state"]}"]["#{job["id"]}"] = job
    end

    # returns a hash of all jobs in current tube
    def self.parseTube(tube)
      bslog "Parsing tube `#{tube}'"

      raise NotConnected if !is_connected?

      # make sure we're only modifying current tube
      @@pool.use(tube)
      @@pool.watch(tube)
      @@connection = @@pool.last_conn
      tubes = @@pool.list_tubes
      tubes["#{@@connection.addr}"].each { |t| @@pool.ignore(t) unless t == tube }
      bslog "Connected at tube `#{@@pool.list_tube_used}'"

      @@t ||= {} # our temp tube

      # initiate our hash
      @@t = { "jobs" =>
              { "reserved" => {}, 
                "ready" => {},
                "buried" => {},
              },
              "watching" => 0,
              "using" => 0,
              "waiting" => 0}
      
      #data = @@pool.stats_tube(tube)
      for state in @@states do
        @@current_state = state

        # figure out which jobs we will be processing
        puts "| State: #{@@current_state} => { `#{@@connection.reserved_jobs.inspect}', `#{@@connection.list_all_jobs.inspect}', `#{@@connection.buried_jobs.inspect}' }"
        tube_jobs = 
          (state == "reserved") ? @@connection.reserved_jobs : 
          (state == "ready")    ? @@connection.list_all_jobs : 
                                  @@connection.buried_jobs

        # no jobs in this state, parse next state
        next if tube_jobs.nil?

        # process jobs in current state of tube
        for job_id in tube_jobs do
          parseJob(job_id)
        end

      end
=begin
      while true
        # retrieve
          job = popJob(@@pool)

        break if job.nil? # no more jobs in queue
        
        # process
          parseJob(job)
          pushJob(job)
      end
=end

      # restore original queue
      # rebuildTube(tube)
      return @@t
    end

    #def self.pushJob(job)
    #  bslog "Pushing job into #{@@pool.list_tube_used} with id #{job.id}"
    #  @@jobs["#{@@current_state}"]["#{job.id}"] = job unless @@jobs["#{@@current_state}"].has_key?("#{job.id}")
    #end

    # gets job from front of queue
    #def self.popJob(connection)
    #  bslog "Popping job from #{connection.list_tube_used}"
    #  connection.reserve(PULLING_TIMER) rescue nil
    #end

    #def self.rebuildTube(tube)
    #  @@pool.watch(tube)
    #  @@pool.use(tube)

    #  return if @@jobs["#{@@current_state}"].empty?
    #  @@jobs["#{@@current_state}"].each do |id, j|
    #    j.release
    #  end

    #  # clear up
    #  for state in @@states do
    #    @@jobs["#{state}"].clear
    #  end
    #end

    def self.buryJob(id, pri = 65536)
      return if !is_connected?

      bslog "Burying job with id #{id}"
      job = getJob(id)

      raise InvalidOperation if (job["state"] != "reserved")

      @@pool.bury(id, pri)

    end

    def self.releaseJob(id, pri=65536, delay=0)
      return if !is_connected?

      job = getJob(id)

      # make sure we're releasing a reserved job
      raise InvalidOperation if (job["state"] != "reserved")

      # job is reserved, release it
      @@pool.release(job["id"], pri, delay)

    end

    # helper method for fetching a hash of job stats using their id
    def self.getJob(id)
      @@pool.job_stats(id) #.fetch("#{@@pool.last_conn.addr}")
    end

  end
end
