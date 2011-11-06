require 'rubygems'
require 'rumpy/version'
require 'rumpy/bot'

module Rumpy

  # Start bot in new process,
  # detach this process and save the pid of process in pid_file
  def self.start(bot)
    pf = pid_file bot
    return false if File.exist? pf

    bot.log_file = "#{bot.class.to_s.downcase}.log"

    pid = fork do
      bot.start
    end
    Process.detach pid
    File.open(pf, 'w') do |file|
      file.puts pid
    end
    true
  end # def self.start(bot)

  # Determine the name of pid_file, read pid from this file
  # and try to kill process with this pid
  def self.stop(bot)
    pf = pid_file bot
    return false unless File.exist? pf
    begin
      File.open(pf) do |file|
        Process.kill :TERM, file.gets.strip.to_i
      end
    ensure
      File.unlink pf
    end
    true
  end # def self.stop(bot)

  # Start bot without detaching
  def self.run(bot)
    bot.start
  end

  # Determine the name of file where thid pid will stored to
  def self.pid_file(bot)
    pid_file = bot.pid_file
    pid_file = bot.class.to_s.downcase + '.pid' unless pid_file
    pid_file
  end
end # module Rumpy
