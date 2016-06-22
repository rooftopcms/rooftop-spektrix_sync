# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'rooftop/spektrix_sync/version'

Gem::Specification.new do |spec|
  spec.name          = "rooftop-spektrix_sync"
  spec.version       = Rooftop::SpektrixSync::VERSION
  spec.authors       = ["Ed Jones"]
  spec.email         = ["ed@errorstudio.co.uk"]
  spec.summary       = %q{A set of tasks to sync events between Spektrix and Rooftop CMS}
  spec.description   = %q{A set of tasks to sync events between Spektrix and Rooftop CMS}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake"

  spec.add_dependency 'colorize'
  spec.add_dependency 'activesupport'
  spec.add_dependency 'require_all'
  spec.add_dependency "rooftop-events"
  spec.add_dependency 'rooftop', '~> 0.0.7'
  spec.add_dependency "spektrix"
end
