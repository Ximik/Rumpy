Gem::Specification.new do |s|
  s.name                = "rumpy"
  s.version             = "0.8"
  s.default_executable  = "rumpy"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=

  s.authors           = [ "Tsokurov A.G. <me@ximik.net>", "Pogoda M.V. <mpogoda@jabber.kiev.ua>" ]
  s.date              = %q{2011-06-13}
  s.description       = %q{Simple framework to quickly make up jabber bot}
  s.email             = %q{mpogoda@lavabit.com}
  s.files             = [ "lib/rumpy.rb" ]
  s.homepage          = %q{https://github.com/Ximik/Rumpy}
  s.require_paths     = [ "lib" ]
  s.rubygems_version  = %q{1.8.5}
  s.summary           = %q{Rumpy == jabber bot}

  if s.respond_to? :specification_version then
    s.specification_version = 3
  end
end
