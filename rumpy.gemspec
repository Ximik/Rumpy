Gem::Specification.new do |s|
  s.name              = 'rumpy'
  s.version           = '0.9.9'

  s.authors           = [ 'Tsokurov A.G.', 'Pogoda M.V.' ]
  s.date              = '2011-06-17'
  s.description       = 'Rumpy is some kind of framework to make up your own jabber bot quickly.'

  s.email             = [ 'mpogoda@lavabit.com', 'me@ximik.net' ]
  s.files             = [ 'lib/rumpy.rb' , 'README.rdoc' ]
  s.homepage          = 'https://github.com/Ximik/Rumpy'
  s.license           = 'MIT'
  s.summary           = 'Rumpy == jabber bot framework'
  s.extra_rdoc_files  = [ 'README.rdoc' ]
  s.rdoc_options.concat [ '--main', 'README.rdoc' ]

  s.add_dependency 'activerecord', '>3.0'
  s.add_dependency 'xmpp4r', '>= 0.5'
end
