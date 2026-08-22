# frozen_string_literal: true

require 'minitest/autorun'
require 'pgn'
require_relative '../lib/variation_builder'

class TestVariationBuilder < Minitest::Test
  def setup
    @builder = VariationBuilder.new
  end

  def test_format_centipawns
    assert_equal '+1.4', @builder.send(:format_centipawns, 140)
    assert_equal '+2.5', @builder.send(:format_centipawns, 250)
    assert_equal '+0.5', @builder.send(:format_centipawns, 50)
  end

  def test_format_centipawns_mate_score
    # Mate scores are typically > 900 centipawns
    assert_match(/\+M\d+/, @builder.send(:format_centipawns, 950))
  end

  def test_format_centipawns_mate_in_1
    # Mate in 1: score 999 (1000 - 1)
    assert_equal '+M1', @builder.send(:format_centipawns, 999)
  end

  def test_format_centipawns_mate_in_5
    # Mate in 5: score 995 (1000 - 5)
    assert_equal '+M5', @builder.send(:format_centipawns, 995)
  end

  def test_build_variation_sequence_with_simple_moves
    starting_fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
    uci_moves = %w[e2e4 e7e5 g1f3]

    sequence = @builder.build_variation_sequence(starting_fen, uci_moves, 3)

    assert_equal 3, sequence.size
    assert_equal 'e4', sequence[0].notation
    assert_equal 'e5', sequence[1].notation
    assert_equal 'Nf3', sequence[2].notation
  end

  def test_build_variation_sequence_respects_max_moves
    starting_fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
    uci_moves = %w[e2e4 e7e5 g1f3 b8c6 f1c4]

    sequence = @builder.build_variation_sequence(starting_fen, uci_moves, 3)

    assert_equal 3, sequence.size
  end

  def test_build_variation_sequence_handles_invalid_move
    starting_fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
    uci_moves = %w[e2e4 invalid_move g1f3]

    sequence = @builder.build_variation_sequence(starting_fen, uci_moves, 3)

    # Should stop at the invalid move
    assert_equal(['e4'], sequence.map(&:notation))
  end

  def test_build_variation_sequence_skips_null_moves
    starting_fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
    uci_moves = ['e2e4', nil, '--', 'e7e5']

    sequence = @builder.build_variation_sequence(starting_fen, uci_moves, 4)

    # Should skip nil and '--' moves
    assert_equal 2, sequence.size
    assert_equal 'e4', sequence[0].notation
    assert_equal 'e5', sequence[1].notation
  end

  def test_add_best_move_variation
    move = PGN::MoveText.new('e4')
    starting_fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
    analysis_data = {
      best_move_analysis: {
        move: 'g1f3',
        variation: %w[b8c6 f1c4]
      },
      best_score: 50,
      played_score: -100,
      centipawn_loss: 150
    }

    @builder.add_best_move_variation(move, starting_fen, analysis_data)

    assert_equal 1, move.variations.size
    variation = move.variations[0]

    assert_equal 3, variation.size
    assert_equal 'Nf3', variation[0].notation
    assert_match(/Better line/, variation[0].comment)
    assert_match(/\+1\.5/, variation[0].comment)
  end

  def test_add_best_move_variation_with_nil_best_move
    move = PGN::MoveText.new('e4')
    starting_fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
    analysis_data = {
      best_move_analysis: {
        move: nil,
        variation: []
      },
      best_score: 50,
      played_score: -100,
      centipawn_loss: 150
    }

    @builder.add_best_move_variation(move, starting_fen, analysis_data)

    # Should not add variation when best_move is nil
    assert_empty move.variations if move.variations
  end
end
