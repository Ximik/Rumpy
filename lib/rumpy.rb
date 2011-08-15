require 'rubygems'
require 'xmpp4r/client'
require 'xmpp4r/roster'
require 'xmpp4r/version'
require 'active_record'
require 'logger'

module Rumpy

  # Create new instance of `botclass`, start it in new process,
  # detach this process and save the pid of process in pid_file
  def self.start(botclass)
    bot = botclass.new
    pf = pid_file bot
    return false if File.exist? pf
    pid = fork do
      bot.start
    end
    Process.detach pid
    File.open(pf, 'w') do |file|
      file.puts pid
    end
    true
  end # def self.start(botclass)

  # Determine the name of pid_file, read pid from this file
  # and try to kill process with this pid
  def self.stop(botclass)
    pf = pid_file botclass.new
    return false unless File.exist? pf
    begin
      File.open(pf) do |file|
        Process.kill :TERM, file.gets.strip.to_i
      end
    ensure
      File.unlink pf
    end
    true
  end # def self.stop(botclass)

  # Create new instance of `botclass` and start it without detaching
  def self.run(botclass)
    botclass.new.start
  end

  # Determine the name of file where thid pid will stored to
  def self.pid_file(bot)
    pid_file = bot.pid_file
    pid_file = bot.class.to_s.downcase + '.pid' if pid_file.nil?
    pid_file
  end

  # include this module into your bot's class
  module Bot
    attr_reader :pid_file


    # one and only public function, defined in this module
    # simply initializes bot's variables, connection, etc.
    # and starts bot
    def start
      @log_file             ||= STDERR
      @log_level            ||= Logger::INFO
      @logger                 = Logger.new @log_file, @log_shift_age, @log_shift_size
      @logger.level           = @log_level
      @logger.progname        = @log_progname
      @logger.formatter       = @log_formatter
      @logger.datetime_format = "%Y-%m-%d %H:%M:%S"

      @logger.info 'starting bot'
      init
      connect
      prepare_users

      set_subscription_callback
      set_message_callback
      set_iq_callback

      start_backend_thread

      @logger.info 'Bot is going ONLINE'
      send_msg Jabber::Presence.new(nil, @status, @priority)

      Signal.trap :TERM do |signo|
        @logger.info 'Bot is unavailable'
        send_msg Jabber::Presence.new.set_type :unavailable

        @queues.each do |user, queue|
          queue.enq :halt
        end
        until @queues.empty?
          sleep 1
        end
        @client.close

        @logger.info 'terminating'
        @logger.close
        exit
      end

      Thread.stop
    rescue => e
      general_error e
      exit
    end # def start

    private

    def init
      @logger.debug 'initializing some variables'

      xmppconfig  = YAML::load_file @config_path + '/xmpp.yml'
      @logger.info 'loaded xmpp.yml'
      @logger.debug "xmpp.yml: #{xmppconfig.inspect}"
      @lang       = YAML::load_file @config_path + '/lang.yml'
      @logger.info 'loaded lang.yml'
      @logger.debug "lang.yml: #{@lang.inspect}"
      @jid        = Jabber::JID.new xmppconfig['jid']
      @priority   = xmppconfig['priority']
      @status     = xmppconfig['status']
      @password   = xmppconfig['password']
      @client     = Jabber::Client.new @jid
      Jabber::Version::SimpleResponder.new(@client, @bot_name || self.class.to_s, @bot_version || '1.0.0', RUBY_PLATFORM)

      if @models_path then
        dbconfig  = YAML::load_file @config_path + '/database.yml'
        @logger.info 'loaded database.yml'
        @logger.debug "database.yml: #{dbconfig.inspect}"
        ActiveRecord::Base.establish_connection dbconfig
        @logger.info 'database connection established'
        Dir[@models_path].each do |file|
          self.class.require file
          @logger.info "added models file '#{file}'"
        end
      end

      @main_model = Object.const_get @main_model.to_s.capitalize
      @logger.info "main model set to #{@main_model}"
      def @main_model.find_by_jid(jid)
        super jid.strip.to_s
      end

      @queues = Hash.new do |h, k|
        h[k]  = Queue.new
      end
    end # def init

    def connect
      @logger.debug 'establishing xmpp connection'

      @client.connect
      @client.auth @password
      @roster = Jabber::Roster::Helper.new @client
      @roster.wait_for_roster

      @logger.info 'xmpp connection established'
    end

    def prepare_users
      @logger.debug 'clear wrong users'

      @roster.items.each do |jid, item|
        user = @main_model.find_by_jid jid
        if user.nil? or item.subscription != :both then
          @logger.info "deleting from roster user with jid #{jid}"
          item.remove
        end
      end
      @main_model.find_each do |user|
        items = @roster.find user.jid
        if items.empty? then
          @logger.info "deleting from database user with jid #{user.jid}"
          user.destroy
        else
          start_user_thread user
        end
      end

      @main_model.connection_pool.release_connection
    end # def prepare_users

    def set_subscription_callback
      @roster.add_subscription_request_callback do |item, presence|
        jid = presence.from
        @roster.accept_subscription jid
        send_msg presence.answer.set_type :subscribe
        send_msg Jabber::Message.new(jid, @lang['hello']).set_type :chat

        @logger.info "#{jid} just subscribed"
      end
      @roster.add_subscription_callback do |item, presence|
        begin
          case presence.type
          when :unsubscribed, :unsubscribe
            @logger.info "#{item.jid} wanna unsubscribe"
            @queues[item.jid.strip.to_s].enq :unsubscribe
            item.remove
          when :subscribed
            user = @main_model.new
            user.jid = item.jid.strip.to_s
            user.save
            start_user_thread user

            @logger.info "added new user: #{user.jid}"
            send_msg Jabber::Message.new(item.jid, @lang['authorized']).set_type :chat
          end
        rescue ActiveRecord::StatementInvalid
          statement_invalid
          retry
        rescue ActiveRecord::ConnectionTimeoutError
          connection_timeout_error
          retry
        rescue => e
          general_error e
        end
      end
    end # def set_subscription_callback

    def set_message_callback
      @client.add_message_callback do |msg|
        if msg.type != :error and msg.body and msg.from then
          if @roster[msg.from] and @roster[msg.from].subscription == :both then
            @logger.debug "got normal message #{msg}"

            @queues[msg.from.strip.to_s].enq msg
          else # if @roster[msg.from] and @roster[msg.from].subscription == :both
            @logger.debug "user not in roster: #{msg.from}"

            send_msg msg.answer.set_body @lang['stranger']
          end # if @roster[msg.from] and @roster[msg.from].subscription == :both
        end # if msg.type != :error and msg.body and msg.from
      end # @client.add_message_callback
    end # def set_message_callback

    def set_iq_callback
      @client.add_iq_callback do |iq|
        @logger.debug "got iq #{iq}"
        if iq.type == :get then # hack for pidgin (STOP USING IT)
          response = iq.answer true
          if iq.elements['time'] == "<time xmlns='urn:xmpp:time'/>" then
            @logger.debug 'this is time request, okay'
            response.set_type :result
            tm = Time.now
            response.elements['time'].add REXML::Element.new('tzo')
            response.elements['time/tzo'].text = tm.xmlschema[-6..-1]
            response.elements['time'].add REXML::Element.new('utc')
            response.elements['time/utc'].text = tm.utc.xmlschema
          else
            response.set_type :error
          end # if iq.elements['time']
          send_msg response
        end
      end
    end # def set_iq_callback

    def start_backend_thread
      Thread.new do
        begin
          loop do
            backend_func().each do |result|
              message = Jabber::Message.new(*result).set_type :chat
              send_msg message if message.body and message.from
            end
          end
        rescue ActiveRecord::StatementInvalid
          statement_invalid
          retry
        rescue ActiveRecord::ConnectionTimeoutError
          connection_timeout_error
          retry
        rescue => e
          general_error e
        end # begin
      end if self.respond_to? :backend_func
    end # def start_backend_thread

    def start_user_thread(user)
      Thread.new(user) do |user|

        loop do
          msg = @queues[user.jid].deq

          begin
            if msg.kind_of? Symbol then # :unsubscribe or :halt
              if msg == :unsubscribe
                @logger.info "removing user #{user.jid}"
                user.destroy
              end
              @queues.delete user.jid
              break
            end

            pars_results = parser_func msg.body
            @logger.debug "parsed message: #{pars_results.inspect}"
            message = do_func user, pars_results
            send_msg msg.answer.set_body message unless message.empty?
          rescue ActiveRecord::StatementInvalid
            statement_invalid
            retry
          rescue ActiveRecord::ConnectionTimeoutError
            connection_timeout_error
            retry
          rescue => e
            general_error e
          end # begin

          @main_model.connection_pool.release_connection
        end # loop do
        Thread.current.join
      end # Thread.new do
    end # def start_user_thread(queue)

    def send_msg(msg)
      return if msg.nil?
      @logger.debug "sending message: #{msg}"
      @client.send msg
    end

    def statement_invalid
      @logger.warn 'Statement Invalid catched'
      @logger.info 'Reconnecting to database'
      @main_model.connection.reconnect!
    end

    def connection_timeout_error
      @logger.warn 'ActiveRecord::ConnectionTimeoutError'
      @logger.info 'sleep and retry again'
      sleep 3
    end

    def general_error(exception)
      @logger.error exception.inspect
      @logger.error exception.backtrace
    end
  end # module Rumpy::Bot
end # module Rumpy
