# frozen_string_literal: true

require_relative 'test_helper'

class RequestBuilderTest < Minitest::Test
  include TestSupport

  def setup
    @config = StockfishPool::Config.new
    @builder = StockfishPool::RequestBuilder.new(@config)
  end

  def build(params)
    @builder.build({ 'fen' => START_FEN }.merge(params))
  end

  def test_defaults_for_interactive_lane
    request = build({})

    assert_equal :interactive, request.lane
    assert_equal({ depth: 16, movetime_ms: 2000, nodes: 2_000_000, multipv: 1 }, request.applied)
    assert_empty request.moves
  end

  def test_clamps_to_lane_ceilings
    interactive = build('depth' => 40, 'movetime_ms' => 60_000, 'nodes' => 10**12, 'multipv' => 50)
    batch = build('lane' => 'batch', 'depth' => 40, 'movetime_ms' => 60_000)

    assert_equal({ depth: 18, movetime_ms: 2000, nodes: 2_000_000, multipv: 3 }, interactive.applied)
    assert_equal [14, 400], [batch.depth, batch.movetime_ms]
  end

  def test_rejects_line_break_injection_anywhere
    injected = "#{START_FEN}\nsetoption name Threads value 1024"

    assert_raises(StockfishPool::InvalidRequest) { build('fen' => injected) }
    assert_raises(StockfishPool::InvalidRequest) { build('moves' => ["e2e4\nquit"]) }
    assert_raises(StockfishPool::InvalidRequest) { build('subject' => "abc\ndef") }
  end

  def test_rejects_malformed_values
    [
      { 'fen' => 'not a fen' }, { 'fen' => nil }, { 'moves' => 'e2e4' }, { 'moves' => ['Nf3'] },
      { 'depth' => 0 }, { 'depth' => '16' }, { 'multipv' => 1.5 }, { 'lane' => 'urgent' },
      { 'moves' => ['e2e4'] * 601 }
    ].each do |params|
      assert_raises(StockfishPool::InvalidRequest, params.inspect) { build(params) }
    end
  end

  def test_rejects_non_object_body
    assert_raises(StockfishPool::InvalidRequest) { @builder.build([START_FEN]) }
  end

  def test_fen_validation
    valid = ['r1bqkbnr/pppp1ppp/2n5/4p3/3PP3/5N2/PPP2PPP/RNBQKB1R b KQkq d3 0 3', '8/8/1k6/3K4/5R2/8/2B5/8 w - - 0 1']
    invalid = ['rnbqqbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', # two black queens, no black king
               'rnbqkbnr/pppppppp/9/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
               'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w QK - 0 1']

    valid.each { |fen| assert StockfishPool::InputValidator.valid_fen?(fen), "expected valid: #{fen}" }
    invalid.each { |fen| refute StockfishPool::InputValidator.valid_fen?(fen), fen }
  end
end
