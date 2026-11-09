# frozen_string_literal: true

require_relative 'test_helper'
require 'rack/test'
require 'json'
require 'tmpdir'
require_relative '../app'

# Rate limits, the shared annotation cache and the untrusted-proxy warning.
class AppPublicLimitsTest < Minitest::Test
  include Rack::Test::Methods

  UNANNOTATED = 'quill-2025-08-06.pgn'

  def setup
    @dir = Dir.mktmpdir('limits-test')
    FileUtils.cp(File.expand_path("data/#{UNANNOTATED}", __dir__), @dir)
    Rack::Attack.reset!
  end

  def teardown
    Rack::Attack.enabled = false
    Rack::Attack.reset!
    FileUtils.rm_rf(@dir)
  end

  def app
    @app ||= LearnerApp.new(pgn_dir: @dir)
  end

  def with_rate_limits
    Rack::Attack.enabled = true
    yield
  ensure
    Rack::Attack.enabled = false
  end

  def login_attempt(remote)
    post '/login', { password: 'guess' }, 'REMOTE_ADDR' => remote
    last_response.status
  end

  def test_login_attempts_are_limited_per_client
    statuses = with_rate_limits { Array.new(7) { login_attempt('203.0.113.7') } }

    assert_equal ([303] * 5) + ([429] * 2), statuses
    assert_operator last_response.headers['retry-after'].to_i, :>, 0
    assert_match(/Too many requests/, JSON.parse(last_response.body)['error'])
  end

  def test_limits_are_per_client_and_ipv6_counts_per_slash_64
    with_rate_limits do
      5.times { |i| login_attempt("2001:db8:1:2::#{i + 1}") }

      assert_equal 429, login_attempt('2001:db8:1:2::99'), 'same /64'
      assert_equal 303, login_attempt('2001:db8:1:3::1'), 'different /64'
      assert_equal 303, login_attempt('203.0.113.8')
    end
  end

  def test_static_assets_are_not_counted
    with_rate_limits do
      700.times { get '/styles/style.css', {}, 'REMOTE_ADDR' => '203.0.113.9' }

      assert_equal 200, last_response.status
      get '/api/session', {}, 'REMOTE_ADDR' => '203.0.113.9'

      assert_equal 200, last_response.status
    end
  end

  # Counts Analyzer instances; answers every search with a quiet position.
  class CountingAnalyzer
    class << self
      attr_accessor :created
    end
    self.created = 0

    def initialize(*)
      self.class.created += 1
    end

    def evaluate_best_move(*) = { score: 10, move: 'e2e4', variation: [] }
    def evaluate_move(*) = { score: -10, move: 'e7e5', variation: [] }
    def close; end
  end

  def load_unannotated
    get '/api/pgn_files'
    id = JSON.parse(last_response.body).first.fetch('id')
    post '/api/load_game', { pgn_file_id: id }.to_json, 'CONTENT_TYPE' => 'application/json'
    last_response.status
  end

  def test_whole_game_analysis_runs_once_per_file
    CountingAnalyzer.created = 0
    Analyzer.stub :new, ->(*args) { CountingAnalyzer.new(*args) } do
      assert_equal 200, load_unannotated
      clear_cookies # a different visitor

      assert_equal 200, load_unannotated
    end

    assert_equal 1, CountingAnalyzer.created
  end

  def test_editing_the_file_invalidates_the_cached_analysis
    CountingAnalyzer.created = 0
    Analyzer.stub :new, ->(*args) { CountingAnalyzer.new(*args) } do
      load_unannotated
      path = File.join(@dir, UNANNOTATED)
      File.write(path, "#{File.read(path)}\n")
      File.utime(Time.now + 5, Time.now + 5, path)
      load_unannotated
    end

    assert_equal 2, CountingAnalyzer.created
  end

  def test_forwarded_for_from_an_untrusted_proxy_is_reported_once
    remote = '10.89.77.1'
    assert_output(nil, /10\.89\.77\.1 carries X-Forwarded-For.*TRUSTED_PROXIES/) do
      2.times { get '/api/session', {}, 'REMOTE_ADDR' => remote, 'HTTP_X_FORWARDED_FOR' => '203.0.113.7' }
    end
    assert_output(nil, '') do
      get '/api/session', {}, 'REMOTE_ADDR' => remote, 'HTTP_X_FORWARDED_FOR' => '203.0.113.7'
    end
  end
end
