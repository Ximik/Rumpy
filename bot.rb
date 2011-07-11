#!/usr/bin/env ruby

require 'rumpy'

bot = Rumpy.new
bot.main_model = :User
bot.parser_func = lambda { |m|
  {:respond => (m == "ты хуй")}
}
bot.do_func = lambda { |model, hash|
  if hash[:respond] then
    "no u"
  end
}
bot.start

