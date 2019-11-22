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
        duration = measure { pipeline.run }
        puts "filters/grok parse rate: #{"%02.0f/sec" % (EVENT_COUNT / duration)}, elapsed: #{duration}s"
      end.to perform_under(max_duration).warmup(1).sample(2).times
    end

  end

  describe "timeout", :performance => true do

    ACCEPTED_TIMEOUT_DEGRADATION = 7.5 # in % (compared to timeout-less run)
    # NOTE: usually bellow 5% on average -> we're expecting every run to be < (+ given%)

    it "has less than #{ACCEPTED_TIMEOUT_DEGRADATION}% overhead" do
      no_timeout_config = <<-CONFIG
        input {
          generator {
            count => 500000
            message => "Mar 16 00:01:25 evita postfix/smtpd[1713]: connect from aaaaaaaa.aaaaaa.net[111.111.11.1]"
          }
        }
        filter {
          grok {
            match => { "message" => [ 
              "foo0: %{NUMBER:bar}", "foo1: %{NUMBER:bar}", "foo2: %{NUMBER:bar}", "foo3: %{NUMBER:bar}", "foo4: %{NUMBER:bar}",
              "foo5: %{NUMBER:bar}", "foo6: %{NUMBER:bar}", "foo7: %{NUMBER:bar}", "foo8: %{NUMBER:bar}", "foo9: %{NUMBER:bar}",
              "%{SYSLOGLINE}" 
            ] }
            timeout_scope => "pattern"
            timeout_millis => 0   # 0 - disabled timeout
          }
        }
        output { null { } }
      CONFIG

      timeout_config = no_timeout_config.
          sub('timeout_scope => "pattern"', 'timeout_scope => "event"').
          sub('timeout_millis => 0', 'timeout_millis => 10000')

      no_timeout_pipeline = new_pipeline_from_string(no_timeout_config)
      no_timeout_duration = measure { no_timeout_pipeline.run } # warmup
      puts "filters/grok(timeout => 0) warmed up in #{no_timeout_duration}"
      gc!
      no_timeout_durations = Array.new(3).map do
        duration = measure { no_timeout_pipeline.run }
        puts "filters/grok(timeout => 0) took #{duration}"
        duration
      end

      timeout_pipeline = new_pipeline_from_string(timeout_config)
      timeout_duration = measure { timeout_pipeline.run } # warmup
      puts "filters/grok(timeout_scope => event) warmed up in #{timeout_duration}"

      expected_duration = avg(no_timeout_durations)
      expected_duration += (expected_duration / 100) * ACCEPTED_TIMEOUT_DEGRADATION
      puts "expected_duration #{expected_duration}"
      gc!
      expect do
        duration = measure { timeout_pipeline.run }
        puts "filters/grok(timeout_scope => event) took #{duration}"
        duration
      end.to perform_under(expected_duration).sample(3).times
    end

  end

  @private

  def measure
    start = Time.now
    yield
    Time.now - start
  end

  def avg(ary)
    ary.inject(0) { |m, i| m + i } / ary.size.to_f
  end

  def gc!
    2.times { JRuby.gc }
  end

end