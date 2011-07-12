#!/usr/bin/env ruby

require 'rumpy'

bot = Rumpy.new
<<<<<<< HEAD
bot.config_path = 'config'
bot.models_path = 'models/*'
bot.main_model = :user
=======
bot.main_model = User
>>>>>>> fd4d87001b4a15b0e320f98174287b3901728f59
bot.parser_func = lambda { |m|
  {:respond => (m == "ты хуй")}
}
bot.do_func = lambda { |model, hash|
  if hash[:respond] then
    "no u"
  end
}
bot.start

