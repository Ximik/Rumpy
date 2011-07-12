#!/usr/bin/env ruby

require 'rumpy'

class MyBot < Rumpy
  def initialize
    Dir[File.dirname(__FILE__) + '/models/*.rb'].each do |file|
      self.class.require file
    end
    super :config_path => 'config', :main_model => User
  end

  def parser_func(m)
    { :respond => ( m == "u r so cute" ) }
  end

  def do_func(model, params)
    "and u r 2 :3" if params[:respond]
  end
end

MyBot.new.start

