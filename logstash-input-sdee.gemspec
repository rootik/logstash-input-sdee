Gem::Specification.new do |s|
  s.name          = 'logstash-input-sdee'
  s.version       = '0.7.8'
  s.license       = 'Apache-2.0'
  s.summary       = 'Logstah SDEE input from Cisco ASA'
  s.description   = 'This Logstash input plugin allows you to call a Cisco SDEE/CIDEE HTTP API, decode the output of it into event(s), and send them on their merry way.'
  s.homepage      = 'http://rubygems.org/gems/logstash-input-sdee'
  s.authors       = ['rootik']
  s.email         = 'roootik@gmail.com'
  s.require_paths = ['lib']

  # Files
  s.files = Dir['lib/**/*','spec/**/*','vendor/**/*','*.gemspec','*.md','CONTRIBUTORS','Gemfile','LICENSE','NOTICE.TXT']
   # Tests
  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  # Special flag to let us know this is actually a logstash plugin
  s.metadata = { "logstash_plugin" => "true", "logstash_group" => "input" }

  # Gem dependencies
  s.add_runtime_dependency "logstash-core-plugin-api", "~> 2.0", '<= 6.0.0'
  #s.add_runtime_dependency 'logstash-codec-plain'
  #s.add_runtime_dependency 'stud', '>= 0.0.22'
  s.add_development_dependency 'logstash-devutils', '>= 0.0.16', '<= 6.0.0'
  s.add_runtime_dependency 'logstash-mixin-http_client', '>= 1.0.0', '<= 6.0.0'
end
