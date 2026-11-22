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
        variation: %w[b8c6 e2e4]
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

  # 14.Qxe4 f5 15.Qe2 e4 16.Nbd2 Rf6 17.a4 a6 18.h3 Rh6 19.a5 Bxh3: twelve
  # plies that stop with White's h-pawn just taken.
  EXCHANGE_FEN = 'r2q1rk1/ppp2ppp/1b1p4/3Pp3/1PB1n1b1/2P2N2/PB2QPPP/RN3RK1 w - - 8 14'
  TWELVE_PLIES = %w[e2e4 f7f5 e4e2 e5e4 b1d2 f8f6 a2a4 a7a6 h2h3 f6h6 a4a5 g4h3].freeze

  def test_build_variation_sequence_continues_through_captures
    sequence = @builder.build_variation_sequence(EXCHANGE_FEN, TWELVE_PLIES + %w[g2h3 h6h3 d8h4], 12)

    assert_equal %w[Bxh3 gxh3 Rxh3], sequence.last(3).map(&:notation)
  end

  def test_build_variation_sequence_adds_only_captures_past_its_length
    sequence = @builder.build_variation_sequence(EXCHANGE_FEN, TWELVE_PLIES, 4)

    assert_equal %w[Qxe4 f5 Qe2 e4], sequence.map(&:notation)
  end

  def test_build_variation_sequence_asks_for_a_continuation_after_a_capture
    asked = []
    continuation = lambda do |fen|
      asked << fen
      { move: 'g2h3', variation: %w[h6h3 d8h4] }
    end

    sequence = @builder.build_variation_sequence(EXCHANGE_FEN, TWELVE_PLIES, 12, continuation: continuation)

    assert_equal 1, asked.size
    assert_equal 'r2q2k1/1pp3pp/pb1p3r/P2P1p2/1PB1p3/2P2N1b/1B1NQPP1/R4RK1 w - - 0 20', asked.first
    assert_equal %w[Bxh3 gxh3 Rxh3], sequence.last(3).map(&:notation)
  end

  def test_build_variation_sequence_does_not_ask_after_a_quiet_move
    continuation = ->(_fen) { flunk 'no continuation is needed after a quiet move' }

    sequence = @builder.build_variation_sequence(EXCHANGE_FEN, TWELVE_PLIES.take(11), 12, continuation: continuation)

    assert_equal 11, sequence.size
  end

  def test_build_variation_sequence_does_not_ask_when_the_line_stopped_on_a_quiet_move
    continuation = ->(_fen) { flunk 'the line already shows the exchange ending' }

    sequence = @builder.build_variation_sequence(EXCHANGE_FEN, TWELVE_PLIES + %w[g2h3 h6h3 d8h4], 12,
                                                 continuation: continuation)

    assert_equal 14, sequence.size
  end

  START_FEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'

  def test_build_variation_sequence_continues_through_checks_and_their_replies
    # 1.e4 f6 2.Qh5+ g6 3.Qxg6+ hxg6 4.d4
    sequence = @builder.build_variation_sequence(START_FEN, %w[e2e4 f7f6 d1h5 g7g6 h5g6 h7g6 d2d4], 3)

    assert_equal %w[e4 f6 Qh5 g6 Qxg6 hxg6], sequence.map(&:notation)
  end

  def test_build_variation_sequence_asks_for_a_continuation_after_a_check
    asked = []
    continuation = lambda do |fen|
      asked << fen
      { move: 'g7g6', variation: %w[c2c3] }
    end

    sequence = @builder.build_variation_sequence(START_FEN, %w[e2e4 f7f6 d1h5], 2, continuation: continuation)

    assert_equal ['rnbqkbnr/ppppp1pp/5p2/7Q/4P3/8/PPPP1PPP/RNB1KBNR b KQkq - 1 2'], asked
    assert_equal %w[e4 f6 Qh5 g6], sequence.map(&:notation)
  end

  def test_build_variation_sequence_does_not_ask_after_mate
    continuation = ->(_fen) { flunk 'there is nothing to continue after mate' }

    # Scholar's mate: 1.e4 e5 2.Bc4 Nc6 3.Qh5 Nf6 4.Qxf7#
    sequence = @builder.build_variation_sequence(START_FEN, %w[e2e4 e7e5 f1c4 b8c6 d1h5 g8f6 h5f7], 12,
                                                 continuation: continuation)

    assert_equal 'Qxf7', sequence.last.notation
  end
end
