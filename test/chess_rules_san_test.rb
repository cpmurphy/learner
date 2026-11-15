# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/chess_rules'

class ChessRulesSanTest < Minitest::Test
  San = ChessRules::San
  START_FEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
  KIWIPETE = 'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1'

  def position(fen)
    ChessRules::Position.from_fen(fen)
  end

  def refusal(fen, san)
    assert_raises(ChessRules::IllegalInput) { San.parse(position(fen), san) }.message
  end

  # Writing every legal move and reading it back gives the same move, in
  # positions with castling, en passant, pins, promotions and disambiguation.
  def test_every_legal_move_round_trips
    [KIWIPETE, 'n1n5/PPPk4/8/8/8/8/4Kppp/5N1N b - - 0 1', '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1'].each do |fen|
      ChessRules::Moves.legal_moves(position(fen)).each do |uci|
        assert_equal uci, San.parse(position(fen), San.write(position(fen), uci)), "#{fen} #{uci}"
      end
    end
  end

  def test_reads_moves
    {
      'e4' => 'e2e4', 'Nf3' => 'g1f3', 'Nxf3' => 'g1f3', 'Nc3+' => 'b1c3', 'Na3!?' => 'b1a3'
    }.each { |san, uci| assert_equal uci, San.parse(position(START_FEN), san), san }
    assert_equal 'e1g1', San.parse(position(KIWIPETE), 'O-O')
    assert_equal 'e1c1', San.parse(position(KIWIPETE), '0-0-0')
    assert_equal 'b7a8n', San.parse(position('r3k3/1P6/8/8/8/8/8/4K3 w - - 0 1'), 'bxa8=N')
    assert_equal 'e5d6', San.parse(position('4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2'), 'exd6')
  end

  def test_writes_the_fewest_hints_that_tell_pieces_apart
    rooks = 'r2qk2r/ppp2ppp/2nbpn2/1N6/5B2/1B3Q1P/PPP2PP1/R4RK1 w kq - 3 13'

    assert_equal 'Rfd1', San.write(position(rooks), 'f1d1')
    assert_equal 'R1a2', San.write(position('4k3/8/8/8/8/R7/8/R3K3 w - - 0 1'), 'a1a2')
    assert_equal 'Nd2', San.write(position('4k3/8/8/8/8/8/8/1N2K3 w - - 0 1'), 'b1d2')
  end

  def test_writes_check_and_mate_marks
    assert_equal 'Qxf7#', San.write(position('r1bqkbnr/pppp1ppp/2n5/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4'), 'h5f7')
    assert_equal 'Bxf7+', San.write(position('r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/8/PPPP1PPP/RNBQK1NR w KQkq - 2 3'), 'c4f7')
    assert_equal 'Bxf7', San.write(position('r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/8/PPPP1PPP/RNBQK1NR w KQkq - 2 3'), 'c4f7',
                                   marks: false)
  end

  def test_writes_castling_and_en_passant
    assert_equal 'O-O-O', San.write(position(KIWIPETE), 'e1c1')
    assert_equal 'exd6', San.write(position('4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2'), 'e5d6')
  end

  def test_refuses_illegal_moves_and_says_why
    pinned = '4k3/4r3/8/8/8/8/4N3/4K3 w - - 0 1'

    assert_equal 'that piece cannot move there', refusal(START_FEN, 'e5')
    assert_equal 'Ke9 is not a move', refusal(START_FEN, 'Ke9')
    assert_equal 'it leaves the king in check', refusal(pinned, 'Nc3')
  end

  def test_refuses_ambiguous_moves_and_wrong_promotions
    assert_equal 'the move is ambiguous', refusal('4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1', 'Nd2')
    assert_equal 'a pawn reaching the last rank must promote', refusal('4k3/1P6/8/8/8/8/8/4K3 w - - 0 1', 'b8')
    assert_equal 'only a pawn reaching the last rank can promote', refusal(START_FEN, 'e4=Q')
  end

  def test_says_why_castling_is_refused
    assert_equal 'pieces stand between the king and the rook', refusal(START_FEN, 'O-O')
    assert_equal 'castling is no longer allowed', refusal(KIWIPETE.sub('KQkq', 'Qkq'), 'O-O')
    assert_equal 'the king cannot castle out of, through or into check',
                 refusal('r3k2r/8/8/8/8/8/5r2/R3K2R w KQkq - 0 1', 'O-O')
  end

  def test_refuses_to_write_an_illegal_move
    assert_raises(ChessRules::IllegalInput) { San.write(position(START_FEN), 'f1c4') }
    assert_raises(ChessRules::IllegalInput) { San.write(position(START_FEN), 'not a move') }
  end
end
