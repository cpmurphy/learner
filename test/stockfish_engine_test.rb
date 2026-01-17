# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/stockfish_engine'

class StockfishEngineTest < Minitest::Test
  def setup
    skip 'Stockfish not found' unless stockfish_available?
    @engine = StockfishEngine.new('stockfish')
  end

  def teardown
    @engine&.close
  end

  def test_engine_starts_and_responds
    assert_predicate @engine, :running?, 'Engine should be running after initialization'
  end

  def test_execute_setoption_command
    result = @engine.execute('setoption name Hash value 64')
    # setoption commands don't return output
    assert_equal '', result
  end

  def test_multipv_sets_option
    @engine.multipv(3)
    # Should not raise an error
    assert_predicate @engine, :running?
  end

  def test_analyze_position
    starting_fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
    result = @engine.analyze(starting_fen, depth: 10)

    refute_nil result
    refute_empty result
    assert_includes result, 'info', 'Analysis should contain info lines'
    assert_includes result, 'bestmove', 'Analysis should contain bestmove'
  end

  def test_analyze_with_multipv
    @engine.multipv(3)
    starting_fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
    result = @engine.analyze(starting_fen, depth: 10)

    # Count how many "multipv" lines there are
    multipv_count = result.scan(/multipv \d+/).length

    assert_operator multipv_count, :>=, 3, 'Should have at least 3 multipv lines'
  end

  def test_position_and_go_commands
    starting_fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
    @engine.execute("position fen #{starting_fen} moves e2e4")
    result = @engine.execute('go depth 10')

    assert_includes result, 'bestmove', 'Should return analysis with bestmove'
  end

  def test_close_shuts_down_engine
    @engine.close

    refute_predicate @engine, :running?, 'Engine should not be running after close'
  end

  def test_engine_error_on_invalid_path
    error = assert_raises(StockfishEngine::EngineError) do
      StockfishEngine.new('/nonexistent/path/to/stockfish')
    end
    assert_match(/not found/, error.message)
  end

  def test_communication_error_when_engine_closed
    @engine.close
    error = assert_raises(StockfishEngine::CommunicationError) do
      @engine.execute('position startpos')
    end
    assert_match(/not running/, error.message)
  end

  private

  def stockfish_available?
    system('which stockfish > /dev/null 2>&1')
  end
end
