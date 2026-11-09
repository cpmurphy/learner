# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/analyzer'

class AnalyzerBackendSelectionTest < Minitest::Test
  TOKEN = 'token-0123456789abcdefghij'
  START_FEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'

  # Minimal local engine that answers configuration and can be made slow.
  class FakeEngine
    attr_reader :commands

    def initialize(delay: 0)
      @delay = delay
      @commands = []
    end

    def execute(command)
      @commands << command
      ''
    end

    def multipv(_value); end

    def analyze(_fen, depth:)
      sleep @delay
      "info depth #{depth} multipv 1 score cp 10 nodes 1 pv e2e4\nbestmove e2e4"
    end
  end

  def test_engine_url_selects_the_service
    analyzer = Analyzer.new(engine_url: 'http://stockfish-pool:4000', engine_token: TOKEN)

    assert_predicate analyzer, :remote?
  end

  def test_engine_url_without_token_fails_clearly
    error = assert_raises(Analyzer::EngineError) do
      Analyzer.new(engine_url: 'http://stockfish-pool:4000', engine_token: '')
    end

    assert_match(/ENGINE_TOKEN/, error.message)
  end

  def test_no_url_means_a_local_engine
    analyzer = Analyzer.new(engine_url: '', engine_override: FakeEngine.new)

    refute_predicate analyzer, :remote?
  end

  def test_engine_override_wins_over_url
    analyzer = Analyzer.new(engine_url: 'http://stockfish-pool:4000', engine_token: TOKEN,
                            engine_override: FakeEngine.new)

    refute_predicate analyzer, :remote?
  end

  def test_local_timeout_raises_timeout_error_and_discards_engine
    engine = FakeEngine.new(delay: 1)
    analyzer = Analyzer.new(engine_override: engine, timeout: 0.05)
    error = assert_raises(Analyzer::TimeoutError) { analyzer.best_moves(START_FEN) }

    assert_match(/timed out after 0.05 seconds/, error.message)
    assert_includes engine.commands, 'quit'
    assert_nil analyzer.instance_variable_get(:@backend)
  end

  def read_timeout(analyzer)
    analyzer.instance_variable_get(:@backend).instance_variable_get(:@client).instance_variable_get(:@read_timeout)
  end

  def test_remote_read_timeout_depends_on_lane
    interactive = Analyzer.new(engine_url: 'http://stockfish-pool:4000', engine_token: TOKEN)
    batch = Analyzer.new(engine_url: 'http://stockfish-pool:4000', engine_token: TOKEN, lane: :batch)

    assert_equal 15, read_timeout(interactive)
    assert_equal 45, read_timeout(batch)
  end

  def test_remote_read_timeout_can_be_overridden_per_lane
    ENV['ENGINE_READ_TIMEOUT_INTERACTIVE'] = '7'
    analyzer = Analyzer.new(engine_url: 'http://stockfish-pool:4000', engine_token: TOKEN)

    assert_equal 7, read_timeout(analyzer)
  ensure
    ENV.delete('ENGINE_READ_TIMEOUT_INTERACTIVE')
  end

  def test_unknown_lane_is_rejected
    error = assert_raises(Analyzer::EngineError) do
      Analyzer.new(engine_url: 'http://stockfish-pool:4000', engine_token: TOKEN, lane: :urgent)
    end

    assert_match(/Unknown lane/, error.message)
  end
end
