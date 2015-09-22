Gem::Specification.new do |s|
  s.name = 'logstash-input-sdee'
  s.version         = '0.4.1'
  s.licenses = ['Apache License (2.0)']
  s.summary = "Poll and decode Cisco SDEE/CIDEE events over HTTP/HTTPS API"
  s.description = "This gem is a logstash plugin required to be installed on top of the Logstash core pipeline using $LS_HOME/bin/plugin install gemname. This gem is not a stand-alone program."
  s.authors = ["rootik"]
  s.email = ["roootik@gmail.com"]
  s.homepage = "https://github.com/rootik/logstash-input-sdee"
  s.require_paths = ["lib"]

  # Files
  s.files = `git ls-files`.split($\)
   # Tests
  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  # Special flag to let us know this is actually a logstash plugin
  s.metadata = { "logstash_plugin" => "true", "logstash_group" => "input" }

  # Gem dependencies
  s.add_runtime_dependency "logstash-core", '>= 1.5.0', '<= 2.0.0'
  s.add_runtime_dependency "logstash/plugin_mixins/http_client"
  s.add_runtime_dependency "uri"
  s.add_runtime_dependency "rexml/document"
  s.add_runtime_dependency "pathname"
  s.add_runtime_dependency "time"
#s.add_runtime_dependency 'logstash-codec-plain'
#s.add_runtime_dependency 'logstash-codec-json'
  s.add_runtime_dependency 'logstash-mixin-http_client', ">= 1.0.1"
  s.add_runtime_dependency 'stud'
  s.add_runtime_dependency 'manticore'

  s.add_development_dependency 'logstash-devutils'
  s.add_development_dependency 'flores'
end
