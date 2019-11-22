# encoding: utf-8
require_relative "../spec_helper"

begin
  require "rspec-benchmark"
rescue LoadError # due testing against LS 5.x
end
RSpec.configure do |config|
  config.include RSpec::Benchmark::Matchers if defined? RSpec::Benchmark::Matchers
end

require "logstash/filters/grok"

describe LogStash::Filters::Grok do

  describe "base-line performance", :performance => true do

    EVENT_COUNT = 300_000
    EXPECTED_MIN_RATE = 15_000 # per second
    # NOTE: based on Travis CI (docker) numbers :
    # logstash_1_d010d1d29244 | LogStash::Filters::Grok
    # logstash_1_d010d1d29244 |   base-line performance
    # logstash_1_d010d1d29244 | filters/grok parse rate: 14464/sec, elapsed: 20.740866999999998s
    # logstash_1_d010d1d29244 | filters/grok parse rate: 29957/sec, elapsed: 10.014199s
    # logstash_1_d010d1d29244 | filters/grok parse rate: 32932/sec, elapsed: 9.109601999999999s

    config <<-CONFIG
      input {
        generator {
          count => #{EVENT_COUNT}
          message => "Mar 16 00:01:25 evita postfix/smtpd[1713]: connect from camomile.cloud9.net[168.100.1.3]"
        }
      }
      filter {
        grok {
          match => { "message" => "%{SYSLOGLINE}" }
          overwrite => [ "message" ]
        }
      }
      output { null { } }
    CONFIG

    it "matches at least #{EXPECTED_MIN_RATE} events/second" do
      max_duration = EVENT_COUNT / EXPECTED_MIN_RATE
      pipeline = new_pipeline_from_string(config)
      expect do
        start = Time.now
        pipeline.run
        duration = (Time.now - start)
        puts "filters/grok parse rate: #{"%02.0f/sec" % (EVENT_COUNT / duration)}, elapsed: #{duration}s"
      end.to perform_under(max_duration).warmup(1).sample(2).times
    end

  end

end