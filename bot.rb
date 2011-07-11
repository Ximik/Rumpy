#!/usr/bin/env ruby

require 'rubygems'
require 'xmpp4r/client'
require 'xmpp4r/roster'

class Bot
  include Jabber
  attr_accessor :backend_func

  def initialize
#    Jabber::debug = true
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
       puts item+' '+presence
    end
  end
  
  def start_message_callback
    @client.add_message_callback do |m|
       puts m
    end
  end
end
bot = Bot.new
bot.start
