#!/usr/bin/env ruby

require 'rumpy'

class MyBot
  include Rumpy

  def initialize
    @config_path = 'config'
    @models_path = '/models/*.rb'
    @main_model  = :user
  end

  def parser_func(m)
    { :respond => ( m == "u r so cute" ) }
  end

  def do_func(model, params)
    "and u r 2 :3" if params[:respond]
  end
end

MyBot.new.start

