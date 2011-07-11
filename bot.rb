#!/usr/bin/env ruby

require 'rumpy'

bot = Rumpy.new
bot.parser_func = lambda { |m|
  {:respond => (m == "ты хуй")}
}
bot.do_func = lambda { |hash|
  if hash[:respond] then
    "no u"
  end
}
bot.start

