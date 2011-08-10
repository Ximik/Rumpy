require 'rubygems'
require 'xmpp4r/client'
require 'xmpp4r/roster'
require 'xmpp4r/version'
require 'active_record'
require 'active_record/validations'
require 'logger'

module Rumpy

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

  def self.run(botclass)
    botclass.new.start
  end

  def self.pid_file(bot)
    pid_file = bot.pid_file
    pid_file = bot.class.to_s.downcase + '.pid' if pid_file.nil?
    pid_file
  end

  module Bot
    attr_reader :pid_file

    def start
      @log_file             ||= STDERR
      @log_level            ||= Logger::INFO
      @logger                 = Logger.new @log_file
      @logger.level           = @log_level
      @logger.datetime_format = "%Y-%m-%d %H:%M:%S"
      Signal.trap :TERM do |signo|
        @logger.info 'terminating'
        @logger.close
        exit
      end

      @logger.info 'starting bot'
      @logger.debug 'initializing some variables'
      init
      @logger.debug 'establishing xmpp connection'
      connect
      @logger.debug 'clear wrong users'
      clear_users
      set_subscription_callback
      set_message_callback
      set_iq_callback
      @logger.info 'Bot is going ONLINE'
      @client.send Jabber::Presence.new.set_priority(@priority).set_status(@status)

      Thread.new do
        begin
          loop do
            backend_func().each do |result|
              send_msg *result
            end
          end
        rescue ActiveRecord::StatementInvalid
          @logger.warn 'Statement Invalid catched'
          @logger.info 'Reconnecting to database'
          reconnect_db!
          retry
        rescue => e
          $logger.error e.inspect
          $logger.error e.backtrace
        end
      end if self.respond_to? :backend_func
      Thread.stop
    end

    private

    def init

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

      @mutexes = Hash.new do |h, k|
        h[k] = Mutex.new
      end
    end

    def connect
      @client.connect
      @client.auth @password
      @roster = Jabber::Roster::Helper.new @client
      @roster.wait_for_roster
      @logger.info 'xmpp connection established'
    end

    def clear_users
      @main_model.find_each do |user|
        items = @roster.find user.jid
        if items.count != 1 then
          @logger.info "deleting from database user with jid #{user.jid}"
          user.destroy
        end
      end
      @roster.items.each do |jid, item|
        user = find_user_by_jid jid
        if user.nil? then
          @logger.info "deleting from roster user with jid #{jid}"
          item.remove
        elsif item.subscription != :both then
          @logger.info "deleting from roster&database user with jid #{jid}"
          item.remove
          user.destroy
        end
      end
    end

    def set_subscription_callback
      @roster.add_subscription_request_callback do |item, presence|
        jid = presence.from
        @roster.accept_subscription jid
        @client.send Jabber::Presence.new.set_type(:subscribe).set_to(jid)
        send_msg jid, @lang['hello']
        @logger.info "#{jid} wanna subscribe"
      end
      @roster.add_subscription_callback do |item, presence|
        begin
          case presence.type
          when :unsubscribed, :unsubscribe
            @logger.info "#{item.jid} wanna unsubscribe"
            item.remove
            remove_jid item.jid
          when :subscribed
            add_jid item.jid
            send_msg item.jid, @lang['authorized']
          end
        rescue ActiveRecord::StatementInvalid
          @logger.warn 'Statement Invalid catched'
          @logger.info 'Reconnecting to database'
          reconnect_db!
          retry
        end
      end
    end

    def find_user_by_jid(jid)
      @main_model.find_by_jid jid
    end

    def reconnect_db!
      @main_model.connection.reconnect!
    end

    def set_message_callback
      @client.add_message_callback do |msg|
        begin
          if msg.type != :error and msg.body and msg.from then
            if user = find_user_by_jid(msg.from) then
              @logger.debug "get normal message from #{msg.from}"
              pars_results = parser_func msg.body
              @logger.debug "parsed message: #{pars_results.inspect}"

              message = ""
              @mutexes[user.jid].synchronize do
                message = do_func user, pars_results
              end
              send_msg msg.from, message
            else
              @logger.debug "uknown user #{msg.from}"
              send_msg msg.from, @lang['stranger']
              items = @roster.find msg.from.strip.to_s
              items.first.last.remove unless items.empty?
            end
          end
        rescue ActiveRecord::StatementInvalid
          @logger.warn 'Statement Invalid catched!'
          @logger.info 'Reconnecting to database'
          reconnect_db!
          retry
        rescue => e
          @logger.error e.inspect
          @logger.error e.backtrace
        end
      end
    end

    def set_iq_callback
      @client.add_iq_callback do |iq|
        @logger.debug "got iq #{iq.inspect}"
        if iq.type == :get then # hack for pidgin (STOP USING IT)
          response = Jabber::Iq.new :error, iq.from
          response.id = iq.id
          if iq.elements["time"] == "<time xmlns='urn:xmpp:time'/>" then
            @logger.debug 'this is time request, okay'
            response.set_type :result
            response.root.add REXML::Element.new('time')
            response.elements['time'].attributes['xmlns'] = 'urn:xmpp:time'
            tm = Time.now
            response.elements['time'].add REXML::Element.new('tzo')
            response.elements['time/tzo'].text = tm.xmlschema[-6..-1]
            response.elements['time'].add REXML::Element.new('utc')
            response.elements['time/utc'].text = tm.utc.xmlschema
           end
          @logger.debug "sending response: #{response}"
          @client.send response
        end
      end
    end

    def send_msg(destination, text)
      return if destination.nil? or text.nil?
      msg = Jabber::Message.new destination, text
      msg.type = :chat
      @logger.debug "sending message: #{msg}"
      @client.send msg
    end

    def add_jid(jid)
      user = @main_model.new
      user.jid = jid.strip.to_s
      user.save
      @logger.info "added new user: #{jid}"
    end

    def remove_jid(jid)
      user = @main_model.find_by_jid jid
      unless user.nil?
        @logger.info "removing user #{jid}"
        user.destroy
      end
    end
  end
end
