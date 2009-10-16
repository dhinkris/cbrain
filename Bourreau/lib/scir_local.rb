
#
# CBRAIN Project
#
# This is a replacement for the drmaa.rb library; this particular subclass
# of class Scir implements a dummy cluster interface that still runs
# jobs locally as standard unix subprocesses.
#
# Original author: Pierre Rioux
#
# $Id$
#

require 'scir'

class ScirLocalSession < Scir::Session

  Revision_info="$Id$"

  Scir.session_subclass = self.to_s

  def job_ps(jid)
    IO.popen("ps -p #{shell_escape(jid)} -O state 2>/dev/null","r") do |i|
      i.readlines.each do |line|
        next unless line.match(/^\s*\d+\s+(\S+)/)
        state = Regexp.last_match[1]
        return Scir::STATE_USER_SUSPENDED if state.match(/[t]/i)
        return Scir::STATE_RUNNING        if state.match(/[sruz]/i)
        #return Scir::STATE_QUEUED_ACTIVE  if state.match(//i)
        #return Scir::STATE_USER_ON_HOLD   if state.match(//i)
        return Scir::STATE_UNDETERMINED
      end
    end
    return Scir::STATE_UNDETERMINED
  end

  def hold(jid)
    true
  end

  def release(jid)
    true
  end

  def suspend(jid)
    Process.kill("STOP",jid.to_i) rescue true
  end

  def resume(jid)
    Process.kill("CONT",jid.to_i) rescue true
  end

  def terminate(jid)
    Process.kill("TERM",jid.to_i) rescue true
  end

  def queue_tasks_tot_max
    cpuinfo = `cat /proc/cpuinfo`.split("\n")
    proclines = cpuinfo.select { |i| i.match(/^processor\s*:\s*/i) }
    [ "unknown", proclines.size.to_s ]
  rescue
    [ "exception", "exception" ]
  end

  private

  def qsubout_to_jid(i)
    id = i.readline  # we must read only ONE line
    if id && id =~ /PID=(\d+)/
      return Regexp.last_match[1]
    end
    raise "Cannot find job ID from bash subshell output"
  end

end

class ScirLocalJobTemplate < Scir::JobTemplate

  Scir.jobtemplate_subclass = self.to_s

  def qsub_command
    raise "Error, this class only handle 'command' as /bin/bash and a single script in 'arg'" unless
      self.command == "/bin/bash" && self.arg.size == 1
    raise "Error: stdin not supported" if self.stdin

    stdout = self.stdout
    stderr = self.stderr

    stdout.sub!(/^:/,"") if stdout
    stderr.sub!(/^:/,"") if stderr

    command = ""
    command += "cd #{shell_escape(self.wd)} || exit 20; " if self.wd
    command += "/bin/bash #{shell_escape(self.arg[0])}"
    command += "  > #{shell_escape(stdout)} "             if stdout
    command += " 2> #{shell_escape(stderr)} "             if stderr
    command += " 2>&1 "                                   if self.join

    command = "bash -c \"echo PID=\\$\\$ ; #{command}\" & "

    return command
  end

end
