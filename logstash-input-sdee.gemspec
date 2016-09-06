Gem::Specification.new do |s|
  s.name        = 'logstash-input-sdee'
  s.version     = '0.7.5'
  s.date        = '2016-08-17'
  s.summary     = "Logstah SDEE input from Cisco ASA"
  s.description = "This Logstash input plugin allows you to call a Cisco SDEE/CIDEE HTTP API, decode the output of it into event(s), and send them on their merry way."
  s.authors     = ["rootik"]
  s.email       = 'roootik@gmail.com'
  s.require_paths = ['lib']

  s.files       = Dir['lib/**/*', 'examples/**/*', '*.gemspec', 'LICENSE', 'Gemfile', 'README.md', 'CHANGELOG.md', 'CONTRIBUTORS']
  s.homepage    =
    'http://rubygems.org/gems/logstash-input-sdee'
  s.metadata = { "logstash_plugin" => "true", "logstash_group" => "input" }
  s.license       = 'Apache-2.0'
  s.metadata = { "logstash_plugin" => "true", "logstash_group" => "input" }
  s.add_runtime_dependency 'logstash-core', '>= 1.4.0', '<= 2.99'
  s.add_runtime_dependency 'logstash-core-plugin-api', '>= 0.60', '<= 2.99'
  s.add_runtime_dependency 'logstash-mixin-http_client', '>= 1.0.0', '<= 6.0.0'
#  s.add_runtime_dependency 'rubysl-rexml', '>= 2.0.0', '<= 3.0.0'
end
