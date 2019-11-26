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

  subject do
    described_class.new(config).tap { |filter| filter.register }
  end

  EVENT_COUNT = 300_000

  describe "base-line performance", :performance => true do

    EXPECTED_MIN_RATE = 15_000 # per second
    # NOTE: based on Travis CI (docker) numbers :
    # logstash_1_d010d1d29244 | LogStash::Filters::Grok
    # logstash_1_d010d1d29244 |   base-line performance
    # logstash_1_d010d1d29244 | filters/grok parse rate: 14464/sec, elapsed: 20.740866999999998s
    # logstash_1_d010d1d29244 | filters/grok parse rate: 29957/sec, elapsed: 10.014199s
    # logstash_1_d010d1d29244 | filters/grok parse rate: 32932/sec, elapsed: 9.109601999999999s

    let(:config) do
      { 'match' => { "message" => "%{SYSLOGLINE}" }, 'overwrite' => [ "message" ] }
    end

    it "matches at least #{EXPECTED_MIN_RATE} events/second" do
      max_duration = EVENT_COUNT / EXPECTED_MIN_RATE
      message = "Mar 16 00:01:25 evita postfix/smtpd[1713]: connect from camomile.cloud9.net[168.100.1.3]"
      expect do
        duration = measure do
          EVENT_COUNT.times { subject.filter(LogStash::Event.new("message" => message)) }
        end
        puts "filters/grok parse rate: #{"%02.0f/sec" % (EVENT_COUNT / duration)}, elapsed: #{duration}s"
      end.to perform_under(max_duration).warmup(1).sample(2).times
    end

  end

  describe "timeout", :performance => true do

    ACCEPTED_TIMEOUT_DEGRADATION = 10 # in % (compared to timeout-less run)
    # NOTE: usually bellow 5% on average -> we're expecting every run to be < (+ given%)

    MATCH_PATTERNS = {
      "message" => [
        "foo0: %{NUMBER:bar}", "foo1: %{NUMBER:bar}", "foo2: %{NUMBER:bar}", "foo3: %{NUMBER:bar}", "foo4: %{NUMBER:bar}",
        "foo5: %{NUMBER:bar}", "foo6: %{NUMBER:bar}", "foo7: %{NUMBER:bar}", "foo8: %{NUMBER:bar}", "foo9: %{NUMBER:bar}",
        "%{SYSLOGLINE}"
      ]
    }

    SAMPLE_MESSAGE = "Mar 16 00:01:25 evita postfix/smtpd[1713]: connect from aaaaaaaa.aaaaaa.net[111.111.11.1]".freeze

    let(:config_wout_timeout) do
      {
        'match' => MATCH_PATTERNS,
        'timeout_millis' => 0   # 0 - disabled timeout
      }
    end

    let(:config_with_timeout) do
      {
        'match' => MATCH_PATTERNS,
        'timeout_scope' => "event",
        'timeout_millis' => 10_000
      }
    end

    it "has less than #{ACCEPTED_TIMEOUT_DEGRADATION}% overhead" do
      filter_wout_timeout = LogStash::Filters::Grok.new(config_wout_timeout).tap(&:register)
      wout_timeout_duration = do_sample_filter(filter_wout_timeout) # warmup
      puts "filters/grok(timeout => 0) warmed up in #{wout_timeout_duration}"
      gc!
      no_timeout_durations = Array.new(3).map do
        duration = do_sample_filter(filter_wout_timeout)
        puts "filters/grok(timeout => 0) took #{duration}"
        duration
      end

      filter_with_timeout = LogStash::Filters::Grok.new(config_with_timeout).tap(&:register)
      with_timeout_duration = do_sample_filter(filter_with_timeout) # warmup
      puts "filters/grok(timeout_scope => event) warmed up in #{with_timeout_duration}"

      expected_duration = avg(no_timeout_durations)
      expected_duration += (expected_duration / 100) * ACCEPTED_TIMEOUT_DEGRADATION
      puts "expected_duration #{expected_duration}"
      gc!
      expect do
        duration = do_sample_filter(filter_with_timeout)
        puts "filters/grok(timeout_scope => event) took #{duration}"
        duration
      end.to perform_under(expected_duration).sample(3).times
    end

    @private

    def do_sample_filter(filter)
      measure do
        for _ in (1..EVENT_COUNT) do # EVENT_COUNT.times without the block cost
          filter.filter(sample_event)
        end
      end
    end

    def sample_event
      LogStash::Event.new("message" => SAMPLE_MESSAGE)
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