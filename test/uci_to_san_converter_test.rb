# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/uci_to_san_converter'

class UciToSanConverterTest < Minitest::Test
  def setup
    @converter = UciToSanConverter.new
    @starting_fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
  end

  def test_convert_pawn_move
    # e2-e4 should be "e4"
    san = @converter.convert(@starting_fen, 'e2e4')
    assert_equal 'e4', san
  end

  def test_convert_knight_move
    # g1-f3 should be "Nf3"
    san = @converter.convert(@starting_fen, 'g1f3')
    assert_equal 'Nf3', san
  end

  def test_convert_pawn_capture
    # Position after 1.e4 e5 2.Nf3 Nc6 3.d4
    fen = 'r1bqkbnr/pppp1ppp/2n5/4p3/3PP3/5N2/PPP2PPP/RNBQKB1R b KQkq d3 0 3'
    # exd4 pawn capture
    san = @converter.convert(fen, 'e5d4')
    assert_equal 'exd4', san
  end

  def test_convert_piece_capture
    # Position where knight can capture
    fen = 'rnbqkb1r/pppp1ppp/5n2/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3'
    # Nxe5
    san = @converter.convert(fen, 'f3e5')
    assert_equal 'Nxe5', san
  end

  def test_convert_kingside_castling
    # Position where white can castle kingside
    fen = 'rnbqkbnr/pppppppp/8/8/8/5N2/PPPPPPPP/RNBQKB1R w KQkq - 0 1'
    san = @converter.convert(fen, 'e1g1')
    assert_equal 'O-O', san
  end

  def test_convert_queenside_castling
    # Position where white can castle queenside
    fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/R3KBNR w KQkq - 0 1'
    san = @converter.convert(fen, 'e1c1')
    assert_equal 'O-O-O', san
  end

  def test_convert_pawn_promotion
    # White pawn on e7 promoting (8th rank is empty at e8)
    fen = 'rnbqkbnr/ppppPppp/8/8/8/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1'
    # Note: this FEN actually has pieces on the 8th rank, so promotion is a capture
    san = @converter.convert(fen, 'e7e8q')
    assert_equal 'exe8=Q', san
  end

  def test_convert_pawn_promotion_non_capture
    # White pawn on e7 promoting without capture (e8 is empty)
    fen = 'rnbq1b1r/ppppPppp/5n2/4k3/8/8/PPPP1PPP/RNBQKBNR w KQ - 0 1'
    san = @converter.convert(fen, 'e7e8q')
    assert_equal 'e8=Q', san
  end

  def test_convert_pawn_promotion_with_capture
    # White pawn on e7 capturing and promoting
    fen = 'rnbqkbnr/ppppPppp/8/8/8/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1'
    san = @converter.convert(fen, 'e7d8q')
    assert_equal 'exd8=Q', san
  end

  def test_convert_null_move
    san = @converter.convert(@starting_fen, '--')
    assert_equal '--', san
  end

  def test_convert_bishop_move
    # Position with bishop move
    fen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1'
    san = @converter.convert(fen, 'f1c4')
    assert_equal 'Bc4', san
  end

  def test_convert_queen_move
    fen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1'
    san = @converter.convert(fen, 'd1h5')
    assert_equal 'Qh5', san
  end

  def test_convert_rook_move
    fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
    san = @converter.convert(fen, 'a1a3')
    # This is technically illegal in the starting position, but tests the conversion logic
    assert_equal 'Ra3', san
  end

  def test_convert_en_passant_capture_by_black
    # Position where black can capture en passant
    # White just played d2-d4, so black's e4 pawn can capture on d3
    fen = 'r1bqk2r/p4pp1/2pb1n1p/n3N3/3Pp3/8/PPP1BPPP/RNBQK2R b KQkq d3 0 12'
    # e4xd3 (en passant capture)
    san = @converter.convert(fen, 'e4d3')
    assert_equal 'exd3', san
  end

  def test_convert_en_passant_capture_by_white
    # Position where white can capture en passant
    # Black just played f7-f5, so white's e5 pawn can capture on f6
    fen = 'rnbqkbnr/pppp2pp/8/4Pp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3'
    # e5xf6 (en passant capture)
    san = @converter.convert(fen, 'e5f6')
    assert_equal 'exf6', san
  end
end
