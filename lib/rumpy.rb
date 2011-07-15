require 'rubygems'
require 'xmpp4r/client'
require 'xmpp4r/roster'
require 'active_record'
require 'active_record/validations'

module Rumpy

  def self.start(botclass)
    pid = fork do
      botclass.new.start
    end
    File.open(botclass.to_s.downcase + '.pid', 'w') do |file|
      file.puts pid
    end
    Process.detach pid
  end

  def self.stop(botclass)
    File.open(botclass.to_s.downcase + '.pid') do |file|
      Process.kill :TERM, file.gets.strip.to_i
    end
    File.unlink botclass.to_s.downcase + '.pid'
  end

  module Bot
    include Jabber

    def start
      init
      connect
      clear_users
      start_subscription_callback
      start_message_callback
      @client.send Presence.new
      Thread.new do
        loop do
          backend_func().each do |result|
            send_msg *result
          end
        end
      end if self.respond_to? :backend_func
      Thread.stop
    end

    private

    def init

      xmppconfig  = YAML::load_file @config_path + '/xmpp.yml'
      @lang       = YAML::load_file @config_path + '/lang.yml'
      @jid        = JID.new xmppconfig['jid']
      @password   = xmppconfig['password']
      @client     = Client.new @jid

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
      @roster = Roster::Helper.new @client
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
          user.remove
        end
      end
    end

    def start_subscription_callback
      @roster.add_subscription_request_callback do |item, presence|
        jid = presence.from
        @roster.accept_subscription jid
        @client.send Presence.new.set_type(:subscribe).set_to(jid)
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
        if msg.type != :error and msg.body and msg.from then
          if user = @main_model.find_by_jid(msg.from) then
            pars = parser_func msg.body
            message = ""
            @mutexes[user.jid].synchronize do
              message = do_func user, pars
            end
            send_msg msg.from, message
          else
            send_msg msg.from, @lang['stranger']
            items = @roster.find msg.from.strip.to_s
            items.first.last.remove unless items.empty?
          end
        end
      end
    end

    def send_msg(destination, text)
      return if destination.nil? or text.nil?
      msg = Message.new destination, text
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
