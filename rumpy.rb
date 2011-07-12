require 'rubygems'
require 'xmpp4r/client'
require 'xmpp4r/roster'
require 'active_record'
require 'active_record/validations'
require 'yaml'

class Rumpy
  include Jabber
  attr_writer :parser_func
  attr_writer :do_func
  attr_writer :backend_func
  attr_writer :config_path
  attr_writer :models_path

  def load_config
    xmppconfig  = YAML::load File.open(@config_path + '/xmpp.yml')
    dbconfig    = YAML::load File.open(@config_path + '/database.yml')
    @lang       = YAML::load File.open(@config_path + '/lang.yml')
    @jid        = JID.new xmppconfig['jid']
    @password   = xmppconfig['password']
    @client     = Client.new @jid
    ActiveRecord::Base.establish_connection dbconfig

    Dir[File.dirname(__FILE__) + "/#{@models_path}/*.rb"].each {|file| self.class.require file }
    self.main_model = @main_model
  end

  def initialize(params)
    @config_path    = params[:config_path]
    @models_path    = params[:models_path]
    @main_model     = params[:main_model]
    @parser_func    = params[:parser_func]
    @do_func        = params[:do_func]
    @backend_func   = params[:backend_func]
  end

  def connect
    @client.connect
    @client.auth @password
    @client.send Presence.new
    @roster = Roster::Helper.new @client
    @roster.wait_for_roster
  end

  def start
    load_config
    connect
    clear_users
    start_subscription_callback
    start_message_callback
    Thread.new do
      loop &@backend_func
    end unless @backend_func.nil?
    Thread.stop
  end

  private

  def main_model=(value)
    @main_model = self.class.const_get(value.to_s.capitalize)
    def @main_model.find_by_jid (jid)
      super jid.strip.to_s
    end
  end

  def clear_users
    @main_model.all.each do |user|
      items = @roster.find user.jid
      user.destroy if items.count != 1
    end
    @roster.items.each do |jid, item|
      user = @main_model.find_by_jid jid
      item.remove if user.nil?
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
      if msg.type != :error and msg.body and @parser_func and @do_func then
        Thread.new do
          if user = @main.model.find_by_jid(msg.from) then
            send_msg msg.from, @do_func.call(user, @parser_func.call(msg.body))
          else
            send_msg item.jid, @lang['stranger']
          end
        end
      end
    end
  end

  def send_msg(destination, text)
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
