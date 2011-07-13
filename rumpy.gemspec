Gem::Specification.new do |s|
  s.name                = "rumpy"
  s.version             = "0.8.4"
  s.default_executable  = "rumpy"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=

  s.authors           = [ "Tsokurov A.G. <me@ximik.net>", "Pogoda M.V. <mpogoda@jabber.kiev.ua>" ]
  s.date              = %q{2011-06-13}
  s.description       = %q{Simple framework to make up jabber bot quickly}
  s.email             = %q{mpogoda@lavabit.com}
  s.files             = [ "lib/rumpy.rb" , "README.rdoc" ]
  s.homepage          = %q{https://github.com/Ximik/Rumpy}
  s.require_paths     = [ "lib" ]
  s.rubygems_version  = %q{1.8.5}
  s.summary           = %q{Rumpy == jabber bot}
  s.extra_rdoc_files  = %w( README.rdoc )
  s.rdoc_options.concat [ '--main', 'README.rdoc' ]

  if s.respond_to? :specification_version then
    s.specification_version = 3
  end

  s.add_dependency 'activerecord', '>3.0'
  s.add_dependency 'xmpp4r', '>= 0.5'
end
