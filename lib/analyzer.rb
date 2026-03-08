# frozen_string_literal: true

require_relative 'stockfish_engine'
require_relative 'analysis_parser'
require 'timeout'

# A thin wrapper that uses the stockfish engine to analyse the position
class Analyzer
  DEFAULT_TIMEOUT = 5 # seconds
  DEFAULT_DEPTH = 18
  DEFAULT_MULTIPV = 3
  MAX_NODES = 1_000_000

  class EngineError < StandardError; end
  class TimeoutError < EngineError; end

  def initialize(options = {})
    @parser = AnalysisParser.new
    @engine_override = options[:engine_override]
    @engine_path = options.fetch(:engine_path, 'stockfish')
    @timeout = options.fetch(:timeout, DEFAULT_TIMEOUT)
    @depth = options.fetch(:depth, DEFAULT_DEPTH)
    @max_nodes = options.fetch(:max_nodes, MAX_NODES)
    initialize_engine
  end

  def best_moves(fen, multipv = DEFAULT_MULTIPV)
    ensure_engine_running
    @engine.multipv(multipv)

    analysis = with_timeout do
      @engine.analyze(fen, depth: @depth)
    end

    @parser.parse(analysis)
  rescue TimeoutError
    raise TimeoutError, "Analysis timed out after #{@timeout} seconds"
  rescue StandardError => e
    handle_engine_error(e)
  end

  def evaluate_move(fen, move)
    ensure_engine_running
    move_str = move ? "moves #{move}" : ''
    @engine.execute("position fen #{fen} #{move_str}")

    analysis = with_timeout do
      @engine.execute("go depth #{@depth} nodes #{@max_nodes}")
    end

    @parser.parse(analysis)[0]
  rescue TimeoutError
    raise TimeoutError, "Move evaluation timed out after #{@timeout} seconds"
  rescue StandardError => e
    handle_engine_error(e)
  end

  def evaluate_best_move(fen)
    best_moves(fen, 1)[0]
  end

  # Assess if a user's move is a good alternative to a known good move.
  #
  # A move is "good enough" if its score is over 250 centipawns (winning),
  # or if its score is at least 80% of the good move's score.
  #
  # @param fen [String] The FEN string of the board position.
  # @param user_move_uci [String] The user's move in UCI format.
  # @param good_move_uci [String] The known good move in UCI format.
  # @return [Boolean] True if the move is good enough, false otherwise.
  def good_enough_move?(fen, user_move_uci, good_move_uci)
    # The suggested move from the PGN is always considered good enough.
    return true if user_move_uci == good_move_uci

    good_move_analysis = evaluate_move(fen, good_move_uci)
    return false unless good_move_analysis

    # The score from `evaluate_move` is from the perspective of the side whose turn it is
    # AFTER the move has been made. We want the score from the perspective of the player
    # who MADE the move, so we negate it.
    good_move_score = -good_move_analysis[:score].to_f

    user_move_analysis = evaluate_move(fen, user_move_uci)
    return false unless user_move_analysis

    user_move_score = -user_move_analysis[:score].to_f

    # A move is good enough if it has a winning advantage on its own (>2.5 pawns).
    return true if user_move_score > 250

    # Or if it's almost as good as the suggested move.
    threshold_multiplier = good_move_score.negative? ? 1.2 : 0.8
    return true if user_move_score >= (good_move_score * threshold_multiplier)

    false
  end

  def close
    @engine&.execute('quit')
  rescue Errno::EPIPE
    # The stockfish engine may raise an EPIPE error if
    # the connection is closed and the engine is not running.
    # This is a workaround to ignore that error.
  ensure
    @engine = nil
  end

  private

  def initialize_engine
    @engine = @engine_override || StockfishEngine.new(@engine_path)
    configure_engine
  rescue StandardError => e
    raise EngineError, "Failed to initialize Stockfish engine: #{e.message}"
  end

  def configure_engine
    @engine.execute("setoption name MultiPV value #{DEFAULT_MULTIPV}")
    @engine.execute('setoption name Hash value 128')
    @engine.execute('setoption name Threads value 1')
  end

  def ensure_engine_running
    return if @engine

    initialize_engine
  end

  def with_timeout(&block)
    Timeout.timeout(@timeout, &block)
  end

  def handle_engine_error(error)
    close
    raise EngineError, "Engine error: #{error.message}"
  end
end
