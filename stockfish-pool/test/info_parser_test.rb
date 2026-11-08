# frozen_string_literal: true

require_relative 'test_helper'

class InfoParserTest < Minitest::Test
  def parse(text)
    StockfishPool::InfoParser.parse(text.lines.map(&:chomp))
  end

  def test_keeps_the_last_line_per_multipv
    result = parse(<<~UCI)
      info depth 10 multipv 1 score cp 30 nodes 10 pv e2e4 e7e5
      info depth 10 multipv 2 score cp 20 nodes 10 pv d2d4 d7d5
      info depth 11 multipv 1 score cp 35 nodes 20 pv e2e4 c7c5 g1f3
      info depth 11 multipv 2 score mate -3 nodes 20 pv d2d4
      bestmove e2e4 ponder c7c5
    UCI

    assert_equal 'e2e4', result[:bestmove]
    assert_equal({ multipv: 1, move: 'e2e4', score: { cp: 35 }, depth: 11, pv: %w[e2e4 c7c5 g1f3] }, result[:lines][0])
    assert_equal({ mate: -3 }, result[:lines][1][:score])
  end

  def test_skips_bound_scores_and_noise
    result = parse(<<~UCI)
      info string NNUE evaluation using nn-1234.nnue
      info depth 12 multipv 1 score cp 50 nodes 10 pv e2e4
      info depth 13 multipv 1 score cp 90 lowerbound nodes 20 pv d2d4
      info depth 13 currmove g1f3 currmovenumber 3
      bestmove e2e4
    UCI

    assert_equal 1, result[:lines].size
    assert_equal({ cp: 50 }, result[:lines][0][:score])
  end

  def test_position_without_legal_moves
    result = parse("info depth 0 score mate 0\nbestmove (none)\n")

    assert_nil result[:bestmove]
    assert_equal [{ multipv: 1, move: nil, score: { mate: 0 }, depth: 0, pv: [] }], result[:lines]
  end
end
