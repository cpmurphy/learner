# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'support/edge_case_generators'

# Checks the oracle and the generators the Stockfish property tests rely on.
# These need no engine, so they also run where Stockfish is not installed.
class EdgeCaseGeneratorsTest < Minitest::Test
  G = PropCheck::Generators

  def perft(position, depth)
    return 1 if depth.zero?

    position.legal_moves.sum { |move| perft(position.play(move), depth - 1) }
  end

  # Published perft counts (chessprogramming.org "Perft Results", positions 3
  # and the promotion position) for positions without castling rights. They
  # cover en passant, en passant pins and every promotion.
  def test_model_matches_known_move_counts
    {
      '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1' => [14, 191, 2812],
      'n1n5/PPPk4/8/8/8/8/4Kppp/5N1N b - - 0 1' => [24, 496, 9483]
    }.each do |fen, counts|
      position = ChessModel::Position.from_fen(fen)

      assert_equal fen, position.to_fen
      assert_equal counts, counts.each_index.map { |index| perft(position, index + 1) }, fen
    end
  end

  def test_model_recognises_checkmate_and_stalemate
    assert_predicate ChessModel::Position.from_fen('rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w - - 1 3'),
                     :checkmate?
    assert_predicate ChessModel::Position.from_fen('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1'), :stalemate?
  end

  def test_model_plays_en_passant_and_promotion
    position = ChessModel::Position.from_fen('4k3/3p4/8/4P3/8/8/6p1/4K3 b - - 3 40')
    position = position.play('d7d5')

    assert_equal '4k3/8/8/3pP3/8/8/6p1/4K3 w - d6 0 41', position.to_fen
    position = position.play('e5d6')

    assert_equal '4k3/8/3P4/8/8/8/6p1/4K3 b - - 0 41', position.to_fen
    assert_equal '4k3/8/3P4/8/8/8/8/4K1n1 w - - 0 42', position.play('g2g1n').to_fen
  end

  def test_every_combination_builds
    rng = Random.new

    EdgeCases::PROMOTION_COMBINATIONS.each do |combination|
      assert_kind_of EdgeCaseScenario, EdgeCases.promotion(**combination, seed: rng.rand(2**31))
    end
    EdgeCases::EN_PASSANT_COMBINATIONS.each do |combination|
      assert_kind_of EdgeCaseScenario, EdgeCases.en_passant(**combination, seed: rng.rand(2**31))
    end
  end

  def test_combinations_cover_every_file_and_piece
    promotions = EdgeCases::PROMOTION_COMBINATIONS
    captures = EdgeCases::EN_PASSANT_COMBINATIONS.reject { |combination| combination[:pinned] }

    assert_equal 2 * 4 * (8 + 7 + 7), promotions.size
    assert_equal([%w[b w], (0..7).to_a, %w[b n q r]], %i[color file piece].map { |key| promotions.map { |c| c[key] }.uniq.sort })
    assert_equal 2 * 14, captures.size
    assert_equal (0..7).to_a, captures.map { |combination| combination[:file] }.uniq.sort
  end

  def test_promotion_scenarios
    PropCheck.forall(EdgeCases.promotion_case) do |scenario|
      color, file, piece = scenario.params.values_at(:color, :file, :piece)
      move = scenario.moves[1]
      promoted = scenario.positions[2].board[ChessModel.parse_square(move[2, 2])]

      assert_scenario_shape(scenario, 'move before, promotion, reply')
      assert_equal "#{'abcdefgh'[file]}#{color == 'w' ? 7 : 2}", move[0, 2], scenario.inspect
      assert_equal ChessModel.piece_for(color, piece), promoted, scenario.inspect
    end
  end

  def test_en_passant_scenarios
    PropCheck.forall(EdgeCases.en_passant_case) do |scenario|
      color, file = scenario.params.values_at(:color, :file)
      pushed_to = [file, color == 'w' ? 4 : 3]

      assert_scenario_shape(scenario, 'double push, capture, reply')
      assert_equal [file, color == 'w' ? 5 : 2], scenario.positions[1].ep, scenario.inspect
      if scenario.kind == :en_passant
        assert_nil scenario.positions[2].board[pushed_to], "The captured pawn is still there: #{scenario.inspect}"
      else
        refute_includes scenario.positions[1].legal_moves, scenario.forbidden, scenario.inspect
      end
    end
  end

  def test_checkmate_and_stalemate_scenarios
    PropCheck.forall(G.one_of(EdgeCases.checkmate_case, EdgeCases.stalemate_case)) do |scenario|
      last = scenario.positions.last

      assert_scenario_shape(scenario, 'move before, final move')
      assert_predicate last, scenario.kind == :checkmate ? :checkmate? : :stalemate?, scenario.inspect
      refute(scenario.positions[0..-2].any? { |position| position.legal_moves.empty? }, scenario.inspect)
    end
  end

  def test_mirroring_twice_gives_the_same_position
    PropCheck.forall(EdgeCases.edge_case) do |scenario|
      scenario.positions.each { |position| assert_equal position, position.flip.flip }
    end
  end

  # The pool's own rules (lib/stockfish_pool/rules) against the model: both
  # must find the same legal moves, and accept every generated line.
  def test_pool_rules_agree_with_the_model
    PropCheck.forall(EdgeCases.edge_case) do |scenario|
      assert_nil StockfishPool::Rules.check!(scenario.positions.first.to_fen, scenario.moves), scenario.inspect
      scenario.positions.each do |position|
        assert_equal position.legal_moves.sort, pool_legal_moves(position.to_fen).sort, position.to_fen
      end
    end
  end

  # The pool accepts only positions the model calls well formed, and refuses a
  # well-formed one (without castling or en passant) only for its material.
  def test_pool_refuses_badly_formed_positions
    accepted = 0
    PropCheck.forall(EdgeCases.well_shaped_fen) do |fen|
      model = ChessModel::Position.from_fen(fen)
      reason = begin
        StockfishPool::Rules.check!(fen, [])
      rescue StockfishPool::Rules::IllegalInput => e
        e.message
      end

      if reason.nil?
        accepted += 1

        assert_predicate model, :well_formed?, fen
      elsif model.well_formed? && fen.split[2..3] == %w[- -]
        assert_match(/more pieces than a game can produce/, reason, fen)
      end
    end

    assert_predicate accepted, :positive?, 'No generated position was accepted'
  end

  private

  def pool_legal_moves(fen)
    position = StockfishPool::Rules::Position.from_fen(fen)
    own = (0..63).select { |square| StockfishPool::Rules::Moves.own_piece?(position, square) }
    own.product((0..63).to_a).flat_map do |from, to|
      base = "#{StockfishPool::Rules.square_name(from)}#{StockfishPool::Rules.square_name(to)}"
      [base, *ChessModel::PROMOTIONS.map { |piece| base + piece }].select do |move|
        StockfishPool::Rules::Moves.legal?(position, move)
      end
    end
  end

  # Positions alternate sides, every move is legal and every position is one
  # Stockfish can be given. Promotion and en passant lines have a reply unless
  # the game is over.
  def assert_scenario_shape(scenario, description)
    positions = scenario.positions

    positions.each { |position| assert_predicate position, :well_formed?, scenario.inspect }
    scenario.moves.each_with_index do |move, index|
      assert_includes positions[index].legal_moves, move, "#{description}: #{scenario.inspect}"
      refute_equal positions[index].side, positions[index + 1].side
    end
    return if scenario.forbidden || %i[checkmate stalemate].include?(scenario.kind)

    assert_equal(positions[2].legal_moves.empty? ? 2 : 3, scenario.moves.size, scenario.inspect)
  end
end
