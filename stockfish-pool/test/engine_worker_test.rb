# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

class EngineWorkerTest < Minitest::Test
  include TestSupport

  def setup
    @dir = Dir.mktmpdir('fake-engine')
    @log = File.join(@dir, 'commands.log')
  end

  def teardown
    @worker&.kill
    FileUtils.rm_rf(@dir)
  end

  def start_worker(mode, overrides = {})
    @config = config(overrides, engine_mode: mode, log: @log)
    @worker = StockfishPool::EngineWorker.new(config: @config, handshake_timeout_s: 1).start
  end

  def commands
    File.readlines(@log, chomp: true)
  end

  def test_search_returns_parsed_lines
    start_worker('normal')
    result = @worker.search(request(@config, 'multipv' => 2))

    assert_equal 'FakeFish 1.0', result[:engine]
    assert_equal 'e2e4', result[:bestmove]
    assert_equal([1, 2], result[:lines].map { |line| line[:multipv] })
  end

  def test_builds_every_command_itself
    start_worker('normal')
    @worker.search(request(@config, 'moves' => %w[e2e4 e7e5], 'depth' => 12, 'multipv' => 2))

    assert_equal(
      ['uci', 'setoption name Threads value 1', 'setoption name Hash value 16', 'isready',
       'ucinewgame', 'setoption name MultiPV value 2', 'isready',
       "position fen #{START_FEN} moves e2e4 e7e5", 'go depth 12 movetime 100 nodes 2000000'],
      commands
    )
  end

  def test_each_search_starts_a_new_game
    start_worker('normal')
    2.times { @worker.search(request(@config)) }

    assert_equal 2, commands.count('ucinewgame')
    assert_equal(1, commands.count { |line| line.start_with?('setoption name MultiPV') })
  end

  def test_overrunning_search_is_stopped
    start_worker('needs_stop')
    result = @worker.search(request(@config))

    assert_equal 'e2e4', result[:bestmove]
    assert_includes commands, 'stop'
    assert_predicate @worker, :alive?
  end

  def test_engine_ignoring_stop_is_killed
    start_worker('ignore_stop')

    assert_raises(StockfishPool::SearchTimeout) { @worker.search(request(@config)) }
    refute_predicate @worker, :alive?
  end

  def test_crash_during_search
    start_worker('crash_on_go')

    assert_raises(StockfishPool::WorkerCrashed) { @worker.search(request(@config)) }
    refute_predicate @worker, :alive?
  end

  def test_handshake_timeout
    @config = config({}, engine_mode: 'no_uciok')
    worker = StockfishPool::EngineWorker.new(config: @config, handshake_timeout_s: 0.2)

    assert_raises(StockfishPool::WorkerCrashed) { worker.start }
  end

  def test_missing_binary
    @config = StockfishPool::Config.new({}, engine_command: ['/nonexistent/stockfish'])

    assert_raises(StockfishPool::WorkerCrashed) { StockfishPool::EngineWorker.new(config: @config).start }
  end

  def test_responsive
    start_worker('normal')

    assert_predicate @worker, :responsive?
    @worker.kill

    refute_predicate @worker, :responsive?
  end
end
