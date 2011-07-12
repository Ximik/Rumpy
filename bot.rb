#!/usr/bin/env ruby

require 'rumpy'

parser_func = lambda { |m|
  { :respond => (m == "ты няша") }
}

do_func = lambda { |model, h|
  "и ты :3" if h[:respond]
}

bot = Rumpy.new(:config_path => 'config', :models_path => 'models', :main_model => :user, :parser_func => parser_func, :do_func => do_func)
bot.start

