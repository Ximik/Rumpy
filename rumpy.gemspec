# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require 'rumpy/version'

Gem::Specification.new do |s|
  s.name              = 'rumpy'
  s.version           = Rumpy::VERSION

  s.authors           = [ 'A.G. Tsokurov', 'M.V. Pogoda' ]
  s.email             = [ 'mpogoda@lavabit.com' ]
  s.date              = Time.now.strftime '%Y-%m-%d'
  s.description       = 'Rumpy is some kind of framework to make up your own jabber bot quickly.'

  s.files             = `git ls-files`.split("\n")
  s.test_files        = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables       = `git ls-files -- bin/*`.split("\n").map do |f|
                                                File.basename(f)
                                              end
  s.require_paths     = ["lib"]
  s.homepage          = 'https://github.com/Ximik/Rumpy'
  s.license           = 'MIT'
  s.summary           = 'Rumpy == jabber bot framework'
  s.extra_rdoc_files  = [ 'README.rdoc' ]
  s.rdoc_options.concat [ '--main', 'README.rdoc' ]

  s.rubyforge_project = 'rumpy'

  s.add_dependency 'activerecord', '>3.0'
  s.add_dependency 'xmpp4r', '>= 0.5'
end
