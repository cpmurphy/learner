# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/analyzer'

class AnalyzerRemoteBackendTest < Minitest::Test
  START_FEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
  Client = StockfishPool::Client

  # Records calls and answers with canned lines, or raises +error+.
  class FakeClient
    attr_reader :calls
    attr_accessor :lines, :error

    def initialize(lines = [])
      @lines = lines
      @calls = []
    end

    def analyze(**params)
      @calls << params
      raise error if error

      Client::Result.new(bestmove: lines.first&.move, lines: lines, engine: 'Fake', lane: params[:lane],
                         applied: {}, ms: 1)
    end
  end

  def line(move, centipawns: nil, mate: nil, pv: [move], multipv: 1)
    Client::Line.new(multipv: multipv, move: move, depth: 16, pv: pv,
                     score: Client::Score.new(cp: centipawns, mate: mate))
  end

  def analyzer(client, **options)
    backend = Analyzer::RemoteBackend.new(client: client, lane: options.fetch(:lane, :interactive),
                                          subject: options[:subject])
    Analyzer.new(backend: backend)
  end

  def test_best_moves_maps_lines_like_the_local_parser
    client = FakeClient.new([line('e2e4', centipawns: 34, pv: %w[e2e4 e7e5 g1f3]), line('d2d4', mate: 3, multipv: 2)])
    result = analyzer(client, subject: 'abc123').best_moves(START_FEN)

    assert_equal [{ score: 34, move: 'e2e4', variation: %w[e7e5 g1f3] },
                  { score: 997, move: 'd2d4', variation: [] }], result
    assert_equal({ lane: :interactive, subject: 'abc123', fen: START_FEN, multipv: 3, depth: 16 }, client.calls.last)
  end

  def test_evaluate_move_sends_the_move_and_node_limit
    client = FakeClient.new([line('e7e5', centipawns: -20)])
    result = analyzer(client, lane: :batch).evaluate_move(START_FEN, 'e2e4')

    assert_equal({ score: -20, move: 'e7e5', variation: [] }, result)
    assert_equal({ lane: :batch, subject: nil, fen: START_FEN, moves: ['e2e4'], multipv: 1, depth: 16,
                   nodes: Analyzer::MAX_NODES }, client.calls.last)
  end

  def test_negative_mate_and_positions_without_moves
    client = FakeClient.new([line('a2a3', mate: -2)])

    assert_equal(-998, analyzer(client).evaluate_best_move(START_FEN)[:score])
    client.lines = [line(nil, mate: 0, pv: [])]

    assert_equal({ score: -1000 }, analyzer(client).evaluate_best_move(START_FEN))
    client.lines = [line(nil, centipawns: 0, pv: [])]

    assert_equal({ score: 0 }, analyzer(client).evaluate_best_move(START_FEN))
  end

  def test_busy_and_quota_become_busy_error_with_retry_after
    client = FakeClient.new
    [Client::Busy, Client::QuotaExceeded].each do |klass|
      client.error = klass.new('slow down', retry_after: 7)
      error = assert_raises(Analyzer::BusyError) { analyzer(client).best_moves(START_FEN) }

      assert_equal 7, error.retry_after
    end
  end

  def test_other_service_errors
    client = FakeClient.new
    client.error = Client::InvalidRequest.new('Invalid FEN')

    assert_raises(Analyzer::InvalidInputError) { analyzer(client).best_moves(START_FEN) }
    client.error = Client::Unavailable.new('down')
    error = assert_raises(Analyzer::EngineError) { analyzer(client).best_moves(START_FEN) }

    refute_kind_of Analyzer::BusyError, error
    assert_match(/Engine service error/, error.message)
  end

  def test_good_enough_move_works_over_the_service
    # Scores are from the side to move after the move, i.e. the opponent's view.
    client = FakeClient.new
    def client.analyze(**params)
      super
      cp = params[:moves] == ['e2e4'] ? -30 : -28
      Client::Result.new(bestmove: 'x', lines: [Client::Line.new(multipv: 1, move: 'e7e5', depth: 16, pv: ['e7e5'],
                                                                 score: Client::Score.new(cp: cp))])
    end

    assert analyzer(client).good_enough_move?(START_FEN, 'd2d4', 'e2e4')
  end

  def test_rejects_bad_input_before_calling_the_service
    client = FakeClient.new

    assert_raises(Analyzer::InvalidInputError) { analyzer(client).best_moves("#{START_FEN}\nquit") }
    assert_empty client.calls
  end
end
