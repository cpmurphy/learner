# frozen_string_literal: true

require 'stockfish'
require 'timeout'

# A class to parse Stockfish analysis output
class AnalysisParser
  CENTIPAWN_PATTERN = /multipv (\d+) score cp (-?\d+) .* pv (\w+)((\s(\w+))*)/
  MATE_PATTERN = /multipv (\d+) score mate (-?\d+) .* pv (\w+)((\s(\w+))*)/
  IMMEDIATE_MATE_PATTERN = /info depth 0 score mate 0/
  IMMEDIATE_DRAW_PATTERN = /info depth 0 score cp 0/

  # Extract the top moves and their corresponding ponder moves
  #
  # rubocop:disable Layout/LineLength
  # analysis is a string like
  # "info depth 14 seldepth 22 multipv 1 score cp 166 nodes 110505 nps 2166764 hashfull 30 tbhits 0 time 51 pv h7h3 e6f7 h3h7 f7e6 e4d5 e6d5 d3e4 d5e4 h7f7 e7f6 f7b3 e4f5 e1f1 f5g4 b3d3 b7g2 h1g2 d8a8 g2g1 g4h3 d3e2
  # info depth 14 seldepth 29 multipv 2 score cp 135 nodes 110505 nps 2166764 hashfull 30 tbhits 0 time 51 pv e4d5 e6d5 d3e4 d5e4 h7f7 e7f6 f7b3 e4f5 e1f1 f5g4 b3d3 b7g2 h1g2 d8a8 g2g1 f6g5 d3e2 g4h4 e3f2 h4h3 f2e1 e8g8
  # info depth 14 seldepth 14 multipv 3 score cp 0 nodes 110505 nps 2166764 hashfull 30 tbhits 0 time 51 pv e1f1 d5f4 f1f4 e5f4 h7h3 e6e5 e3f4 e5f6 h3h4 f6e6 h4h3 e6f6
  # bestmove h6h3 ponder e6f7"
  # rubocop:enable Layout/LineLength
  def parse(analysis)
    analysis.split("\n").each_with_object([]) do |line, moves|
      next unless line.start_with?('info')

      parse_line(line, moves)
    end
  end

  private

  def parse_line(line, moves)
    return parse_centipawn_score(line, moves) if line.match?(CENTIPAWN_PATTERN)
    return parse_mate_score(line, moves) if line.match?(MATE_PATTERN)
    return moves << { score: -1000 } if line.match?(IMMEDIATE_MATE_PATTERN)

    moves << { score: 0 } if line.match?(IMMEDIATE_DRAW_PATTERN)
  end

  def parse_centipawn_score(line, moves)
    match = line.match(CENTIPAWN_PATTERN)
    index = match[1].to_i - 1
    moves[index] = {
      score: match[2].to_i,
      move: match[3]
    }
    add_variation(moves[index], match[4])
  end

  def parse_mate_score(line, moves)
    match = line.match(MATE_PATTERN)
    index = match[1].to_i - 1
    mate_score = match[2].to_i
    moves[index] = {
      score: calculate_mate_score(mate_score),
      move: match[3]
    }
    add_variation(moves[index], match[4])
  end

  def calculate_mate_score(mate_score)
    base = mate_score.negative? ? -1000 : 1000
    base - mate_score
  end

  def add_variation(move_data, variation_string)
    move_data[:variation] = variation_string.split.map(&:strip) if variation_string
  end
end

# A thin wrapper that uses the stockfish engine to analyse the position
class Analyzer
  DEFAULT_TIMEOUT = 5 # seconds
  DEFAULT_DEPTH = 14
  DEFAULT_MULTIPV = 3
  MAX_NODES = 1_000_000

  class EngineError < StandardError; end
  class TimeoutError < EngineError; end

  def initialize(engine_path = 'stockfish', options = {})
    @parser = AnalysisParser.new
    @engine_path = engine_path
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
    @engine = Stockfish::Engine.new(@engine_path)
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
