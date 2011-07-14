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
    File.open(botclass.to_s + '.pid', 'w') do |file|
      file.puts pid
    end
    Process.detach pid
  end

  def self.stop(botclass)
    File.open(botclass.to_s + '.pid') do |file|
      Process.kill :TERM, file.gets.strip.to_i
    end
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
          send_msg backend_func
        end
      end if self.respond_to? :backend_func
      Thread.stop
  end

  private

  def init
    xmppconfig  = YAML::load File.open(@config_path + '/xmpp.yml')
    @lang       = YAML::load File.open(@config_path + '/lang.yml')
    @jid        = JID.new xmppconfig['jid']
    @password   = xmppconfig['password']
    @client     = Client.new @jid
    if not @models_path.nil? then
      dbconfig    = YAML::load File.open(@config_path + '/database.yml')
      ActiveRecord::Base.establish_connection dbconfig
      Dir[@models_path].each do |file|
        Object.require file
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
      end
      if item.subscription != :both then
        item.remove
        user.remove unless user.nil?
      end
    end
  end

  def start_subscription_callback
    @roster.add_subscription_request_callback do |item, presence|
      Thread.new do
        jid = presence.from
        @roster.accept_subscription jid
        @client.send Presence.new.set_type(:subscribe).set_to(jid)
        send_msg jid, @lang['hello']
      end
    end
    @roster.add_subscription_callback do |item, presence|
      Thread.new do
        case presence.type
        when :unsubscribed
          item.remove
        when :unsubscribe
          remove_jid item.jid
        when :subscribed
          add_jid item.jid
          send_msg item.jid, @lang['authorized']
        end
      end
    end
  end

  def start_message_callback
    @client.add_message_callback do |msg|
      if msg.type != :error and msg.body and msg.from then
        Thread.new do
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
