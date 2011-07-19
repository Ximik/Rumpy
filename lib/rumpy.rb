require 'rubygems'
require 'xmpp4r/client'
require 'xmpp4r/roster'
require 'xmpp4r/version'
require 'active_record'
require 'active_record/validations'

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
      @err_file = if @err_file then
                   File.open(@err_file, 'w')
                 else
                   $stderr
                 end
      Signal.trap :TERM do |signo|
        @err_file.close
        exit
      end

      init
      connect
      clear_users
      start_subscription_callback
      start_message_callback
      @client.send Jabber::Presence.new.set_priority(@priority).set_status(@status)
      Jabber::Version::SimpleResponder.new(@client, @bot_name || self.class.to_s, @bot_version || '1.0.0', RUBY_PLATFORM)
      Thread.new do
        begin
          loop do
            backend_func().each do |result|
              send_msg *result
            end
          end
        rescue => e
          $err_file.puts e.inspect
          $err_file.puts e.backtrace
        end
      end if self.respond_to? :backend_func
      Thread.stop
    end

    private

    def init

      xmppconfig  = YAML::load_file @config_path + '/xmpp.yml'
      @lang       = YAML::load_file @config_path + '/lang.yml'
      @jid        = Jabber::JID.new xmppconfig['jid']
      @priority   = xmppconfig['priority']
      @status     = xmppconfig['status']
      @password   = xmppconfig['password']
      @client     = Jabber::Client.new @jid

      if @models_path then
        dbconfig  = YAML::load_file @config_path + '/database.yml'
        ActiveRecord::Base.establish_connection dbconfig
        Dir[@models_path].each do |file|
          self.class.require file
        end
      end

      @main_model = Object.const_get @main_model.to_s.capitalize
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
    end

    def clear_users
      @main_model.find_each do |user|
        items = @roster.find user.jid
        user.destroy if items.count != 1
      end
      @roster.items.each do |jid, item|
        user = @main_model.find_by_jid jid
        if user.nil? then
          item.remove
          next
        elsif item.subscription != :both then
          item.remove
          user.destroy
        end
      end
    end

    def start_subscription_callback
      @roster.add_subscription_request_callback do |item, presence|
        jid = presence.from
        @roster.accept_subscription jid
        @client.send Jabber::Presence.new.set_type(:subscribe).set_to(jid)
        send_msg jid, @lang['hello']
      end
      @roster.add_subscription_callback do |item, presence|
        case presence.type
        when :unsubscribed, :unsubscribe
          item.remove
          remove_jid item.jid
        when :subscribed
          add_jid item.jid
          send_msg item.jid, @lang['authorized']
        end
      end
    end

    def start_message_callback
      @client.add_message_callback do |msg|
        begin
          if msg.type != :error and msg.body and msg.from then
            if user = @main_model.find_by_jid(msg.from) then
              pars_results = parser_func msg.body

              message = ""
              @mutexes[user.jid].synchronize do
                message = do_func user, pars_results
              end
              send_msg msg.from, message
            else
              send_msg msg.from, @lang['stranger']
              items = @roster.find msg.from.strip.to_s
              items.first.last.remove unless items.empty?
            end
          end
        rescue => e
          @err_file.puts e.inspect
          @err_file.puts e.backtrace
        end
      end
      @client.add_iq_callback do |iq|
        if iq.type == :get then
          response = Jabber::Iq.new :error, iq.from
          response.id = iq.id
          if iq.elements["time"] == "<time xmlns='urn:xmpp:time'/>" then
            response.set_type :result
            response.root.add REXML::Element.new('time')
            response.elements['time'].attributes['xmlns'] = 'urn:xmpp:time'
            tm = Time.now
            response.elements['time'].add REXML::Element.new('tzo')
            response.elements['time/tzo'].text = tm.xmlschema[-6..-1]
            response.elements['time'].add REXML::Element.new('utc')
            response.elements['time/utc'].text = tm.utc.xmlschema
           end
          @client.send response
        end
      end
    end

    def send_msg(destination, text)
      return if destination.nil? or text.nil?
      msg = Jabber::Message.new destination, text
      msg.type = :chat
      @client.send msg
    end

    def add_jid(jid)
      user = @main_model.new
      user.jid = jid.strip.to_s
      user.save
    end

    def remove_jid(jid)
      user = @main_model.find_by_jid jid
      user.destroy unless user.nil?
    end
  end
end
