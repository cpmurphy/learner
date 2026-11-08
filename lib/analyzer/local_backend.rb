# frozen_string_literal: true

require 'timeout'
require_relative '../stockfish_engine'
require_relative '../analysis_parser'

class Analyzer
  # Runs Stockfish in this process (one engine per Analyzer). Used for
  # development, tests and anywhere ENGINE_URL is not set.
  class LocalBackend
    def initialize(engine: nil, engine_path: 'stockfish', timeout: Analyzer::DEFAULT_TIMEOUT)
      @parser = AnalysisParser.new
      @timeout = timeout
      @engine = engine || StockfishEngine.new(engine_path)
      configure_engine
    end

    def best_moves(fen, multipv:, depth:)
      @engine.multipv(multipv)
      analysis = with_timeout { @engine.analyze(fen, depth: depth) }
      @parser.parse(analysis)
    end

    def evaluate_move(fen, move, depth:, nodes:)
      move_str = move ? "moves #{move}" : ''
      @engine.execute("position fen #{fen} #{move_str}")
      analysis = with_timeout { @engine.execute("go depth #{depth} nodes #{nodes}") }
      @parser.parse(analysis)
    end

    def close
      @engine&.execute('quit')
    rescue Errno::EPIPE
      # The engine may already be gone; nothing left to close.
    ensure
      @engine = nil
    end

    private

    def configure_engine
      @engine.execute("setoption name MultiPV value #{Analyzer::DEFAULT_MULTIPV}")
      @engine.execute('setoption name Hash value 128')
      @engine.execute('setoption name Threads value 1')
    end

    def with_timeout(&block)
      Timeout.timeout(@timeout, &block)
    end
  end
end
