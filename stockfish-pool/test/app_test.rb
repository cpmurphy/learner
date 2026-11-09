# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'support/fake_worker'
require 'rack/test'
require 'json'

class AppTest < Minitest::Test
  include Rack::Test::Methods
  include TestSupport

  def app
    @app ||= begin
      @config = config(@overrides || {})
      pool = StockfishPool::Pool.new(config: @config, worker_factory: -> { FakeWorker.new }, logger: null_logger)
      @service = StockfishPool::Service.new(config: @config, pool: pool).start(supervise: false)
      StockfishPool::App.new(service: @service)
    end
  end

  def teardown
    @service&.shutdown
  end

  def analyze(body, token: TOKEN)
    header 'Authorization', "Bearer #{token}" if token
    post '/v1/analyze', body.is_a?(String) ? body : body.to_json, 'CONTENT_TYPE' => 'application/json'
    JSON.parse(last_response.body)
  end

  def test_analyze_returns_lines_and_applied_limits
    body = analyze({ fen: START_FEN, depth: 40, multipv: 2 })

    assert_equal 200, last_response.status
    assert_equal 'e2e4', body['bestmove']
    assert_equal({ 'depth' => 18, 'movetime_ms' => 100, 'nodes' => 2_000_000, 'multipv' => 2 }, body['applied'])
    assert_equal 'interactive', body['lane']
  end

  def test_requires_a_valid_token
    analyze({ fen: START_FEN }, token: nil)

    assert_equal 401, last_response.status
    analyze({ fen: START_FEN }, token: 'wrong-token-0123456789abcdef')

    assert_equal 401, last_response.status
  end

  def test_rejects_injection_with_422
    body = analyze({ fen: "#{START_FEN}\nsetoption name Threads value 1024" })

    assert_equal 422, last_response.status
    assert_equal 'invalid_request', body['error']
  end

  def test_rejects_bad_json_and_large_bodies
    analyze('{not json')

    assert_equal 400, last_response.status
    analyze({ fen: START_FEN, padding: 'x' * 20_000 })

    assert_equal 413, last_response.status
  end

  def test_subject_quota_returns_429_with_retry_after
    @overrides = { 'SUBJECT_BURST_SEC' => '1', 'SUBJECT_ENGINE_SEC_PER_MIN' => '1' }
    app
    @service.quota(:interactive).charge('client-1', 5)
    body = analyze({ fen: START_FEN, subject: 'client-1' })

    assert_equal 429, last_response.status
    assert_equal 'quota_exceeded', body['error']
    assert_operator last_response.headers['Retry-After'].to_i, :>=, 1
  end

  def test_global_budget_returns_429
    @overrides = { 'GLOBAL_ENGINE_SEC_PER_MIN' => '1' }
    app
    @service.instance_variable_get(:@budget).charge(2)
    body = analyze({ fen: START_FEN })

    assert_equal 429, last_response.status
    assert_equal 'busy', body['error']
  end

  def test_requires_json_content_type
    header 'Authorization', "Bearer #{TOKEN}"
    post '/v1/analyze', { fen: START_FEN }.to_json, 'CONTENT_TYPE' => 'application/x-www-form-urlencoded'

    assert_equal 415, last_response.status
  end

  def test_healthz_needs_no_token
    get '/healthz'
    body = JSON.parse(last_response.body)

    assert_equal 200, last_response.status
    assert_equal 'ok', body['status']
    assert_equal 2, body['workers'].size
  end

  def test_unknown_route_is_json_404
    get '/v1/nope'

    assert_equal 401, last_response.status
    header 'Authorization', "Bearer #{TOKEN}"
    get '/v1/nope'

    assert_equal 404, last_response.status
  end
end
