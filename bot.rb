#!/usr/bin/env ruby

require 'rubygems'
require 'xmpp4r/client'
require 'xmpp4r/roster'
require 'active_record'
require 'active_record/validations'
require 'yaml'

Dir[File.dirname(__FILE__) + '/models/*.rb'].each {|file| require file }

class Bot
  include Jabber
  attr_accessor :parser_func
  attr_accessor :backend_func

  def initialize
    xmppconfig = YAML::load File.open('config/xmpp.yml')
    dbconfig = YAML::load File.open('config/database.yml')
    @jid = JID.new xmppconfig['jid']
    @password = xmppconfig['password']
    @client = Client.new @jid
    ActiveRecord::Base.establish_connection dbconfig
  end

  def connect
    @client.connect
    @client.auth @password
    @client.send Presence.new
    @roster = Roster::Helper.new @client
    @roster.wait_for_roster
  end

  def start
    connect
    clear_users
    start_subscription_callback
    start_message_callback
    Thread.new do
      loop do
        @backend_func.call
      end
    end unless backend_func.nil?
    Thread.stop
  end

  private 

  def clear_users
    User.all.each do |user|
      items = @roster.find user.jid
      user.destroy if items.count != 1
    end
    @roster.items.each do |jid, item|
      user = User.find_by_jid jid.strip.to_s
      item.remove if user.nil?
    end
  end

  def start_subscription_callback
    @roster.add_subscription_request_callback do |item, presence|
      if item.nil?
        jid = presence.from
        @roster.accept_subscription jid
        @client.send Presence.new.set_type(:subscribe).set_to(jid)
        send_msg "hello", jid
      end
    end
    @roster.add_subscription_callback do |item, presence|
      case presence.type
      when :unsubscribed
        item.remove
      when :unsubscribe
        remove_jid item.jid.strip.to_s
      when :subscribed
        add_jid item.jid.strip.to_s
      end
    end
  end
  
  def start_message_callback
    @client.add_message_callback do |m|
       puts m.from
    end
  end

  def send_msg(text, destination)
    msg = Message.new
    msg.type = :chat
    msg.to = destination
    msg.body = text
    @client.send msg
  end

  def add_jid(jid)
    user = User.new
    user.jid = jid
    user.save
  end

  def remove_jid(jid)
    user = User.find_by_jid jid
    user.destroy unless user.nil?
  end

end
bot = Bot.new
bot.start
