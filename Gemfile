source 'https://rubygems.org'

gemspec

logstash_path = ENV["LOGSTASH_PATH"] || ENV["LS_HOME"] || "../../logstash"
unless Dir.exist?(logstash_path)
  warn "could not find LS repository at: #{logstash_path.inspect} try export LOGSTASH_PATH=..."
end

gem 'logstash-core', path: "#{logstash_path}/logstash-core"
# NOTE: need to keep this till all plugin dependencies get updated
# (as a plugin's gemspec tends to list other plugins as dependencies)
gem 'logstash-core-plugin-api', path: "#{logstash_path}/logstash-core-plugin-api"

# gem 'logstash-devutils', path: '../logstash-devutils'
gem 'logstash-devutils', github: 'kares/logstash-devutils', branch: 'redo-java-pipeline'
