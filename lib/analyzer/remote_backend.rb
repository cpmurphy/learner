# frozen_string_literal: true

require 'stockfish_pool_client'
require_relative '../analysis_parser'

class Analyzer
  # Sends searches to a stockfish-pool service and converts its results into
  # the same hashes LocalBackend returns ({ score:, move:, variation: }, with
  # scores from the side to move's point of view and mates mapped by
  # AnalysisParser.mate_score).
  class RemoteBackend
    # Batch work (whole-game analysis) waits out a busy service, honouring its
    # Retry-After, for up to this many seconds in total before giving up.
    # Interactive requests never wait: the visitor gets a 429 straight away.
    DEFAULT_BATCH_BUSY_WAIT_S = 90
    MAX_SINGLE_WAIT_S = 15

    def initialize(client:, lane: :interactive, subject: nil, batch_busy_wait_s: DEFAULT_BATCH_BUSY_WAIT_S,
                   sleeper: ->(seconds) { sleep(seconds) })
      @client = client
      @lane = lane
      @subject = subject
      @busy_wait_left = lane == :batch ? batch_busy_wait_s : 0
      @sleeper = sleeper
    end

    def best_moves(fen, multipv:, depth:)
      to_analysis(search(fen: fen, multipv: multipv, depth: depth))
    end

    def evaluate_move(fen, move, depth:, nodes:)
      to_analysis(search(fen: fen, moves: move ? [move] : [], multipv: 1, depth: depth, nodes: nodes))
    end

    # The service owns the engines; there is nothing to release here.
    def close; end

    private

    def search(**params)
      @client.analyze(lane: @lane, subject: @subject, **params)
    rescue StockfishPool::Client::Busy, StockfishPool::Client::QuotaExceeded => e
      retry if waited_out?(e.retry_after)
      raise Analyzer::BusyError.new(e.message, retry_after: e.retry_after)
    rescue StockfishPool::Client::InvalidRequest => e
      raise Analyzer::InvalidInputError, e.message
    rescue StockfishPool::Client::Error => e
      raise Analyzer::EngineError, "Engine service error: #{e.message}"
    end

    # Sleeps before a retry while this backend's waiting allowance lasts (it
    # covers the whole analysis, not each search). Returns false when spent.
    def waited_out?(retry_after)
      wait = (retry_after || 1).to_f.clamp(0.5, MAX_SINGLE_WAIT_S)
      return false if wait > @busy_wait_left

      @busy_wait_left -= wait
      @sleeper.call(wait)
      true
    end

    def to_analysis(result)
      result.lines.map { |line| to_move(line) }
    end

    # A line without a move means the side to move has no legal moves: the
    # local parser reports checkmate as -1000 and stalemate as 0.
    def to_move(line)
      return { score: line.score.mate? ? -1000 : 0 } if line.move.nil?

      score = line.score.mate? ? AnalysisParser.mate_score(line.score.mate) : line.score.cp
      { score: score, move: line.move, variation: line.pv.drop(1) }
    end
  end
end
