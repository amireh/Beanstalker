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

    @@pool = nil
    @@connection = nil
    @@t = {}
    @@states = ["reserved", "ready", "buried"]


    # MUST call before any other
    # args: valid, active beanstalk-client connection
    def self.setHandler(pool, options)
      @@pool = pool
      @@connection = @@pool.open_connection(options["host"], options["port"])
      raise CouldNotConnect if @@pool.nil? || @@connection.nil?
    end

    def self.is_connected?
      return !@@pool.nil?
    end

    # returns a hash that contains all
    # information for a certain job
    def self.parseJob(idJob)
      raise NotConnected if !is_connected?

      # get stats
      job = @@connection.job_stats(idJob)
      # get job body
      job["body"] = @@connection.peek_job(idJob).body

      # store job info
      @@t["jobs"]["#{job["state"]}"]["#{job["id"]}"] = job
      return job
    end

    # returns a hash of all jobs in current tube
    def self.parseTube(tube)
      raise NotConnected if !is_connected?

      # make sure we're only modifying current tube
      @@pool.use(tube)
      @@pool.watch(tube)
      # ignore all other tubes
      tubes = @@pool.list_tubes
      tubes["#{@@connection.addr}"].each { |t| @@pool.ignore(t) unless t == tube }

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
      
      for state in @@states do
        @@current_state = state

        begin
        # figure out which jobs we will be processing
        tube_jobs = 
          (state == "reserved") ? @@connection.list_jobs_reserved : 
          (state == "ready")    ? @@connection.list_jobs_ready : 
                                  @@connection.list_jobs_buried
        rescue Exception => e
        end
        # no jobs in this state, parse next state
        next if tube_jobs.nil?

        # process jobs in current state of tube
        for job_id in tube_jobs do
          parseJob(job_id)
        end

      end

      return @@t
    end

    def self.deleteJob(id)
      return if !is_connected?
 
      @@connection.delete(id)
    end

    # helper method for fetching a hash of job stats using their id
    def self.getJob(id)
      @@connection.job_stats(id) #.fetch("#{@@pool.last_conn.addr}")
    end

    def self.kickTube(nrJobs)
      @@connection.kick_jobs(nrJobs)
    end
  end
end
