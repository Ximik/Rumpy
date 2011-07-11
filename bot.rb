#!/usr/bin/env ruby

require 'rumpy'

bot = Rumpy.new
bot.config_path = 'config'
bot.models_path = 'models/*'
bot.main_model = :user
bot.parser_func = lambda { |m|
  {:respond => (m == "ты хуй")}
}
bot.do_func = lambda { |model, hash|
  if hash[:respond] then
    "no u"
  end
}
bot.start

