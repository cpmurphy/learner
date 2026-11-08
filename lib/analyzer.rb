# frozen_string_literal: true

require_relative 'uci_input_validator'
require 'timeout'

# Analyses positions with Stockfish, either in this process (LocalBackend) or
# through a stockfish-pool service (RemoteBackend) when ENGINE_URL is set.
# The public API is the same either way.
class Analyzer
  DEFAULT_TIMEOUT = 5 # seconds, local engine only
  DEFAULT_DEPTH = 16
  DEFAULT_MULTIPV = 3
  MAX_NODES = 1_000_000
  DEFAULT_REMOTE_READ_TIMEOUT = 40 # seconds; covers queue wait plus search

  class EngineError < StandardError; end
  class TimeoutError < EngineError; end

  # The engine service is at capacity or the caller is over its quota.
  class BusyError < EngineError
    attr_reader :retry_after

    def initialize(message = nil, retry_after: nil)
      super(message)
      @retry_after = retry_after
    end
  end

  InvalidInputError = UciInputValidator::InvalidInputError

  # Options:
  #   :engine_url      stockfish-pool URL (default ENV['ENGINE_URL']); unset means a local engine
  #   :engine_token    bearer token for the service (default ENV['ENGINE_TOKEN'])
  #   :lane            :interactive (default) or :batch, for the service
  #   :subject         per-caller quota key for the service, e.g. a hashed client IP
  #   :engine_path     local Stockfish binary
  #   :engine_override a local engine object (tests); forces the local backend
  #   :backend         a ready-made backend (tests)
  #   :timeout, :depth, :max_nodes
  def initialize(options = {})
    @options = options
    @timeout = options.fetch(:timeout, DEFAULT_TIMEOUT)
    @depth = options.fetch(:depth, DEFAULT_DEPTH)
    @max_nodes = options.fetch(:max_nodes, MAX_NODES)
    initialize_backend
  end

  def remote?
    @backend.is_a?(RemoteBackend)
  end

  def best_moves(fen, multipv = DEFAULT_MULTIPV)
    UciInputValidator.validate_fen!(fen)
    with_backend('Analysis') { |backend| backend.best_moves(fen, multipv: multipv, depth: @depth) }
  end

  def evaluate_move(fen, move)
    UciInputValidator.validate_fen!(fen)
    UciInputValidator.validate_uci_move!(move) if move
    with_backend('Move evaluation') do |backend|
      backend.evaluate_move(fen, move, depth: @depth, nodes: @max_nodes)
    end[0]
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
    @backend&.close
  ensure
    @backend = nil
  end

  private

  def with_backend(action)
    initialize_backend unless @backend
    yield @backend
  rescue Timeout::Error
    close # the engine may still be searching; never reuse it
    raise TimeoutError, "#{action} timed out after #{@timeout} seconds"
  rescue InvalidInputError, EngineError
    raise
  rescue StandardError => e
    handle_engine_error(e)
  end

  def initialize_backend
    @backend = build_backend
  rescue StandardError => e
    raise EngineError, "Failed to initialize Stockfish engine: #{e.message}"
  end

  def build_backend
    return @options[:backend] if @options[:backend]

    url = @options.fetch(:engine_url) { ENV.fetch('ENGINE_URL', nil) }.to_s.strip
    return local_backend if @options[:engine_override] || url.empty?

    remote_backend(url)
  end

  def local_backend
    LocalBackend.new(engine: @options[:engine_override], engine_path: @options.fetch(:engine_path, 'stockfish'),
                     timeout: @timeout)
  end

  def remote_backend(url)
    token = @options.fetch(:engine_token) { ENV.fetch('ENGINE_TOKEN', nil) }
    raise ArgumentError, 'ENGINE_TOKEN must be set when ENGINE_URL is' if token.to_s.empty?

    read_timeout = Integer(ENV.fetch('ENGINE_READ_TIMEOUT', DEFAULT_REMOTE_READ_TIMEOUT))
    client = StockfishPool::Client.new(url: url, token: token, read_timeout: read_timeout)
    RemoteBackend.new(client: client, lane: @options.fetch(:lane, :interactive), subject: @options[:subject])
  end

  def handle_engine_error(error)
    close
    raise EngineError, "Engine error: #{error.message}"
  end
end

require_relative 'analyzer/local_backend'
require_relative 'analyzer/remote_backend'
