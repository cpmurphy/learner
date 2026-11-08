# frozen_string_literal: true

require_relative 'test_helper'

# Runs only when a real Stockfish binary is available (ENGINE_PATH or PATH).
class StockfishIntegrationTest < Minitest::Test
  include TestSupport

  ENGINE = ENV.fetch('ENGINE_PATH') do
    ENV['PATH'].split(File::PATH_SEPARATOR).map { |dir| File.join(dir, 'stockfish') }.find { |p| File.executable?(p) }
  end

  def setup
    skip 'Stockfish not installed' unless ENGINE
    @config = StockfishPool::Config.new({ 'INTERACTIVE_MAX_MOVETIME_MS' => '500' }, engine_command: [ENGINE])
    @worker = StockfishPool::EngineWorker.new(config: @config).start
  end

  def teardown
    @worker&.stop
  end

  def test_finds_mate_in_one
    # White to move: Qh5xf7 is mate (scholar's mate pattern).
    fen = 'r1bqkbnr/pppp1ppp/2n5/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4'
    result = @worker.search(request(@config, 'fen' => fen, 'depth' => 10))

    assert_equal 'h5f7', result[:bestmove]
    assert_equal({ mate: 1 }, result[:lines].first[:score])
    assert_match(/Stockfish/, result[:engine])
  end

  def test_multipv_and_movetime_ceiling
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = @worker.search(request(@config, 'depth' => 18, 'multipv' => 3))
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_equal 3, result[:lines].size
    assert_operator elapsed, :<, 1.5
  end

  def test_checkmated_position
    fen = 'rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3'
    result = @worker.search(request(@config, 'fen' => fen))

    assert_nil result[:bestmove]
    assert_equal({ mate: 0 }, result[:lines].first[:score])
  end

  def test_stalemated_position
    fen = '7k/5Q2/6K1/8/8/8/8/8 b - - 0 1'
    result = @worker.search(request(@config, 'fen' => fen))

    assert_nil result[:bestmove]
    assert_equal({ cp: 0 }, result[:lines].first[:score])
  end
end
