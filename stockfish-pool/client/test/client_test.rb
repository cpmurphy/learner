# frozen_string_literal: true

# Contract tests: the client against the real StockfishPool::App, served by an
# in-process Puma server, with fake engine workers behind it.
require_relative '../../test/test_helper'
require_relative '../../test/support/fake_worker'
require_relative '../lib/stockfish_pool_client'
require 'puma'
require 'puma/server'
require 'puma/log_writer'
require 'socket'

class ClientTest < Minitest::Test
  include TestSupport

  def start_server(overrides = {}, factory: -> { FakeWorker.new })
    @config = config(overrides)
    pool = StockfishPool::Pool.new(config: @config, worker_factory: factory, logger: null_logger)
    @service = StockfishPool::Service.new(config: @config, pool: pool).start(supervise: false)
    @server = Puma::Server.new(StockfishPool::App.new(service: @service), nil,
                               min_threads: 1, max_threads: 8, log_writer: Puma::LogWriter.null)
    port = @server.add_tcp_listener('127.0.0.1', 0).addr[1]
    @server.run
    "http://127.0.0.1:#{port}"
  end

  def client(url, token: TOKEN, retries: 0)
    StockfishPool::Client.new(url: url, token: token, retries: retries, retry_delay: 0.01, read_timeout: 5)
  end

  def teardown
    @server&.stop(true)
    @service&.shutdown
  end

  def test_analyze_returns_typed_result
    result = client(start_server).analyze(fen: START_FEN, moves: ['e2e4'], depth: 40, multipv: 1, subject: 'abc')

    assert_equal 'e2e4', result.bestmove
    assert_equal StockfishPool::Client::Score.new(cp: 20, mate: nil), result.lines.first.score
    assert_equal({ depth: 18, movetime_ms: 100, nodes: 2_000_000, multipv: 1 }, result.applied)
    assert_equal :interactive, result.lane
  end

  def test_sends_lane_and_moves
    url = start_server
    client(url).analyze(fen: START_FEN, moves: %w[e2e4 e7e5], lane: :batch)
    request = FakeWorker.registry.last(2).flat_map(&:searches).last

    assert_equal :batch, request.lane
    assert_equal %w[e2e4 e7e5], request.moves
  end

  def test_wrong_token
    url = start_server

    assert_raises(StockfishPool::Client::Unauthorized) do
      client(url, token: 'wrong-token-0123456789abcdef').analyze(fen: START_FEN)
    end
  end

  def test_invalid_request
    error = assert_raises(StockfishPool::Client::InvalidRequest) do
      client(start_server).analyze(fen: "#{START_FEN}\nquit")
    end

    assert_match(/Invalid FEN/, error.message)
  end

  def test_busy_carries_retry_after
    url = start_server({ 'GLOBAL_ENGINE_SEC_PER_MIN' => '1' })
    @service.instance_variable_get(:@budget).charge(5)
    error = assert_raises(StockfishPool::Client::Busy) { client(url).analyze(fen: START_FEN) }

    assert_operator error.retry_after, :>=, 1
  end

  def test_quota_exceeded
    url = start_server({ 'SUBJECT_BURST_SEC' => '1' })
    @service.instance_variable_get(:@quota).charge('client-1', 5)

    assert_raises(StockfishPool::Client::QuotaExceeded) { client(url).analyze(fen: START_FEN, subject: 'client-1') }
  end

  def test_engine_failure_is_unavailable_and_retried
    url = start_server
    workers = FakeWorker.registry.last(2)
    workers.each { |worker| worker.failure = StockfishPool::WorkerCrashed.new('boom') }

    assert_raises(StockfishPool::Client::Unavailable) { client(url, retries: 1).analyze(fen: START_FEN) }
    assert_equal(2, workers.sum { |worker| worker.searches.size })
  end

  def test_unreachable_service
    port = TCPServer.open('127.0.0.1', 0) { |socket| socket.addr[1] } # a port nobody listens on

    assert_raises(StockfishPool::Client::Unavailable) { client("http://127.0.0.1:#{port}").analyze(fen: START_FEN) }
  end

  def test_health
    health = client(start_server).health

    assert_equal 'ok', health['status']
  end

  def test_rejects_bad_configuration
    assert_raises(ArgumentError) { StockfishPool::Client.new(url: 'ftp://x', token: TOKEN) }
    assert_raises(ArgumentError) { StockfishPool::Client.new(url: 'http://x', token: '') }
  end
end
