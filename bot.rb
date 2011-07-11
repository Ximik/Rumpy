#!/usr/bin/env ruby

require 'rubygems'
require 'xmpp4r/client'
require 'xmpp4r/roster'
require 'active_record'

class Bot
  include Jabber
  attr_accessor :backend_func

  def initialize
    @jid = JID::new 'test@ximik.net'
    @password = 'test'
    @client = Client.new @jid
  end

  def connect
    @client.connect
    @client.auth @password
    @client.send Presence.new
    @roster = Roster::Helper.new @client
  end

  def start
    connect
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

  def start_subscription_callback
    @roster.add_subscription_request_callback do |item, presence|
      if presence.type == :subscribe and item.nil?
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
        remove_jid item.jid.node
      when :subscribed
        add_jid item.jid.node
      end
    end
  end
  
  def start_message_callback
    @client.add_message_callback do |m|
       puts m
    end
  end

  def send_msg(text, destination)
    msg = Message::new
    msg.to = destination
    msg.body = text
    @client.send msg
  end

  def add_jid(jid)
  end

  def remove_jid(jid)
  end

end
bot = Bot.new
bot.start
