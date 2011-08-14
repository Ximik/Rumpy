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
  end

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
  end

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
      if @logger.nil? then # if user haven't created his own logger
        @log_file             ||= STDERR
        @log_level            ||= Logger::INFO
        @logger                 = Logger.new @log_file
        @logger.level           = @log_level
        @logger.datetime_format = "%Y-%m-%d %H:%M:%S"
      end
      Signal.trap :TERM do |signo|
        @logger.info 'terminating'
        @logger.close
        exit
      end

      @logger.info 'starting bot'
      init
      connect
      clear_users

      set_subscription_callback
      set_message_callback
      set_iq_callback

      start_backend_thread

      @logger.info 'Bot is going ONLINE'
      @client.send Jabber::Presence.new.set_priority(@priority).set_status(@status)

      Thread.stop
    end

    private

    def start_user_thread(usermq)
      Thread.new do
        usermq.thread = Thread.current
        loop do
          Thread.stop if usermq.queue.empty?
          msg = usermq.queue.deq
          usermq.mutex.synchronize do
            begin
              pars_results = parser_func msg.body
              @logger.debug "parsed message: #{pars_results.inspect}"
              send_msg msg.answer.set_body do_func(usermq.user, pars_results)
            rescue ActiveRecord::StatementInvalid
              @logger.warn 'Statement Invalid catched!'
              @logger.info 'Reconnecting to database'
              @main_model.connection.reconnect!
              retry
            rescue ActiveRecord::ConnectionTimeoutError
              @logger.warn 'ActiveRecord::ConnectionTimeoutError'
              @logger.info 'sleep and retry again'
              sleep 3
              retry
            rescue => e
              @logger.error e.inspect
              @logger.error e.backtrace
            end # begin
          end # synchronize
        end
      end
    end

    def start_backend_thread
      Thread.new do
        begin
          loop do
            backend_func().each do |result|
              send_msg Jabber::Message.new(*result).set_type :chat
            end
          end
        rescue ActiveRecord::StatementInvalid
          @logger.warn 'Statement Invalid catched'
          @logger.info 'Reconnecting to database'
          @main_model.connection.reconnect!
          retry
        rescue => e
          $logger.error e.inspect
          $logger.error e.backtrace
        end
      end if self.respond_to? :backend_func
    end

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

      Struct.new "UserMQT", :user, :mutex, :queue, :thread
      @mqs = Hash.new do |h, k|
        h[k] = Struct::UserMQT.new nil, Mutex.new, Queue.new, nil
      end
    end

    def connect
      @logger.debug 'establishing xmpp connection'

      @client.connect
      @client.auth @password
      @roster = Jabber::Roster::Helper.new @client
      @roster.wait_for_roster

      @logger.info 'xmpp connection established'
    end

    def clear_users
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
          @mqs[user.jid].user = user
          start_user_thread @mqs[user.jid]
        end
      end

      @main_model.connection_pool.release_connection
    end

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
            @mqs[item.jid.strip.to_s].queue.clear
            @mqs[item.jid.strip.to_s].mutex.lock
            @logger.info "#{item.jid} wanna unsubscribe"
            item.remove
            remove_jid item.jid
          when :subscribed
            add_jid item.jid
            send_msg Jabber::Message.new(item.jid, @lang['authorized']).set_type :chat
          end
        rescue ActiveRecord::StatementInvalid
          @logger.warn 'Statement Invalid catched'
          @logger.info 'Reconnecting to database'
          @main_model.connection.reconnect!
          retry
        end
      end
    end

    def set_message_callback
      @client.add_message_callback do |msg|
        if msg.type != :error and msg.body and msg.from then
          if @roster[msg.from] and @roster[msg.from].subscription == :both then
            @logger.debug "got normal message from #{msg.from}"

            @mqs[msg.from.strip.to_s].queue.enq msg
            @mqs[msg.from.strip.to_s].thread.run
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
          if iq.elements["time"] == "<time xmlns='urn:xmpp:time'/>" then
            @logger.debug 'this is time request, okay'
            response.set_type :result
            tm = Time.now
            response.elements['time'].add REXML::Element.new('tzo')
            response.elements['time/tzo'].text = tm.xmlschema[-6..-1]
            response.elements['time'].add REXML::Element.new('utc')
            response.elements['time/utc'].text = tm.utc.xmlschema
          else
            response.set_type :error
          end
          send_msg response
        end
      end
    end

    def send_msg(msg)
      return if msg.nil?
      @logger.debug "sending message: #{msg}"
      @client.send msg
    end

    def add_jid(jid)
      user = @main_model.new
      user.jid = jid.strip.to_s
      user.save
      @mqs[user.jid].user = user
      start_user_thread @mqs[user.jid]
      @logger.info "added new user: #{jid}"
    end

    def remove_jid(jid)
      user = @main_model.find_by_jid jid
      unless user.nil?
        @logger.info "removing user #{jid}"

        @mqs[user.jid].thread.kill
        user.destroy
      end
    end
  end
end
