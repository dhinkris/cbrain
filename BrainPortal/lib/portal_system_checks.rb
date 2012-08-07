
#
# CBRAIN Project
#
# Copyright (C) 2008-2012
# The Royal Institution for the Advancement of Learning
# McGill University
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.  
#

# This class contains methods invoked at boot time for
# the Portal to perform essential validations of the state of
# the system.
class PortalSystemChecks < CbrainChecker #:nodoc:
  
  Revision_info=CbrainFileRevision[__FILE__]

  def self.puts(*args) #:nodoc:
    Rails.logger.info("\e[33m" + args.join("\n") + "\e[0m") rescue nil
    Kernel.puts(*args)
  end

  #Checks for pending migrations, stops the boot if it detects a problem. Must be run first
  def self.a010_check_if_pending_database_migrations

    #-----------------------------------------------------------------------------
    puts "C> Checking for pending migrations..."
    #-----------------------------------------------------------------------------
    
    if defined? ActiveRecord
      pending_migrations = ActiveRecord::Migrator.new(:up, 'db/migrate').pending_migrations
      if pending_migrations.any?
        puts "C> \t- You have #{pending_migrations.size} pending migrations:"
        pending_migrations.each do |pending_migration|
          puts "C> \t\t- %4d %s" % [pending_migration.version, pending_migration.name]
        end
        puts "C> \t- Please run \"rake db:migrate RAILS_ENV=#{Rails.env}\" to update"
        puts "C> \t  your database then try again."
        Kernel.exit(10)
      end
    end
  end
    


  def self.a020_check_database_sanity

    #----------------------------------------------------------------------------
    puts "C> Checking if the BrainPortal database needs a sanity check..."
    #----------------------------------------------------------------------------

    unless PortalSanityChecks.done? 
      puts "C> \t- Error: You must check the sanity of the models. Please run this\n"
      puts "C> \t         command: 'rake db:sanity:check RAILS_ENV=#{Rails.env}'." 
      Kernel.exit(10)
    end
  end

  def self.z000_ensure_we_have_a_local_ssh_agent

    #----------------------------------------------------------------------------
    puts "C> Making sure we have a SSH agent to provide our credentials..."
    #----------------------------------------------------------------------------

    message = 'Found existing agent'
    agent = SshAgent.find_by_name('portal').try(:aliveness)
    unless agent
      begin
        agent = SshAgent.create('portal', "#{Rails.root}/tmp/sockets/ssh-agent.portal.sock")
       #agent = SshAgent.create('portal', "/tmp/ssh-agent.portal.sock")
        message = 'Created new agent'
      rescue
        sleep 1
        agent = SshAgent.find_by_name('portal').try(:aliveness) # in case of race condition
      end
      raise "Error: cannot create SSH agent named 'portal'." unless agent
    end
    agent.apply
    puts "C> \t- #{message}: PID=#{agent.pid} SOCK=#{agent.socket}"

    #----------------------------------------------------------------------------
    puts "C> Making sure we have a CBRAIN key for the agent..."
    #----------------------------------------------------------------------------

    cbrain_identity_file = "#{CBRAIN::Rails_UserHome}/.ssh/id_cbrain_portal"
    if ! File.exists?(cbrain_identity_file)
      puts "C> \t- Creating identity file '#{cbrain_identity_file}'."
      with_modified_env('SSH_ASKPASS' => '/bin/true', 'DISPLAY' => 'none:0.0') do
        system("/bin/bash","-c","ssh-keygen -t rsa -f #{cbrain_identity_file.bash_escape} -C 'CBRAIN_Portal_Key' </dev/null >/dev/null 2>/dev/null")
      end
    end

    if ! File.exists?(cbrain_identity_file)
      puts "C> \t- ERROR: Failed to create identity file '#{cbrain_identity_file}'."
    else
      ok = CBRAIN.with_unlocked_agent do
        with_modified_env('SSH_ASKPASS' => '/bin/true', 'DISPLAY' => 'none:0.0') do
          agent.add_key_file(cbrain_identity_file) rescue nil # will raise exception if anything wrong
        end
      end
      if ok
        puts "C> \t- Added identity to agent from file: '#{cbrain_identity_file}'."
      else
        puts "C> \t- ERROR: cannot add identity from file: '#{cbrain_identity_file}'."
        puts "C> \t  You might want to add the identity yourself manually."
      end
    end

    #----------------------------------------------------------------------------
    puts "C> Starting automatic Agent Locker in background..."
    #----------------------------------------------------------------------------

    allworkers = WorkerPool.find_pool(PortalAgentLocker)

    allworkers.each do |worker|
      puts "C> \t- Found locker already running: '#{worker.pretty_name}'."
    end

    if allworkers.size == 0
      puts "C> \t- No locker processes found. Creating one."

      al_logger = Log4r::Logger.new('AgentLocker')
      al_logger.add(Log4r::RollingFileOutputter.new('agent_locker_outputter',
                      :filename  => "#{Rails.root}/log/AgentLocker..log",
                      :formatter => Log4r::PatternFormatter.new(:pattern => "%d %l %m"),
                      :maxsize   => 1000000, :trunc => 600000))
      al_logger.level = Log4r::INFO # Log4r::INFO or Log4r::DEBUG or other levels...

      WorkerPool.create_or_find_pool(PortalAgentLocker, 1, 
        { :check_interval => 20,
          :worker_log     => al_logger,
          :name           => 'AgentLocker',
        }
      )
    end

  end

end 

