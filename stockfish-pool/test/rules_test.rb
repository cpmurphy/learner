# frozen_string_literal: true

require_relative 'test_helper'

class RulesTest < Minitest::Test
  Rules = StockfishPool::Rules
  KIWIPETE = 'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1'

  def position(fen)
    Rules::Position.from_fen(fen)
  end

  # Every move shaped like UCI from a square holding a piece of the side to move.
  def legal_moves(position)
    own = (0..63).select { |square| Rules::Moves.own_piece?(position, square) }
    own.product((0..63).to_a).flat_map do |from, to|
      base = "#{Rules.square_name(from)}#{Rules.square_name(to)}"
      [base, *%w[q r b n].map { |piece| base + piece }].select { |move| Rules::Moves.legal?(position, move) }
    end
  end

  def perft(position, depth)
    return 1 if depth.zero?

    legal_moves(position).sum do |move|
      perft(position.after(Rules.square(move[0, 2]), Rules.square(move[2, 2]), move[4]), depth - 1)
    end
  end

  # Published perft counts (chessprogramming.org "Perft Results"): Kiwipete and
  # position 5 cover castling (through and out of check), positions 3 and the
  # promotion position cover en passant pins and promotions.
  def test_move_counts_match_known_perft_results
    {
      KIWIPETE => [48, 2039],
      'rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8' => [44, 1486],
      '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1' => [14, 191],
      'n1n5/PPPk4/8/8/8/8/4Kppp/5N1N b - - 0 1' => [24, 496]
    }.each do |fen, counts|
      assert_equal counts, counts.each_index.map { |index| perft(position(fen), index + 1) }, fen
    end
  end

  # The generated move list must be exactly the moves #legal? accepts.
  def test_legal_moves_lists_every_legal_move
    [KIWIPETE, 'rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8', 'n1n5/PPPk4/8/8/8/8/4Kppp/5N1N b - - 0 1'].each do |fen|
      assert_equal legal_moves(position(fen)).sort, Rules::Moves.legal_moves(position(fen)).sort, fen
    end
  end

  def test_fen_round_trips_and_clocks_advance
    assert_equal KIWIPETE, position(KIWIPETE).to_fen
    after_knight = position(TestSupport::START_FEN).after(Rules.square('g1'), Rules.square('f3'))

    assert_equal 'rnbqkbnr/pppppppp/8/8/8/5N2/PPPPPPPP/RNBQKB1R b KQkq - 1 1', after_knight.to_fen
    after_pawn = after_knight.after(Rules.square('e7'), Rules.square('e5'))

    assert_equal 'rnbqkbnr/pppp1ppp/8/4p3/8/5N2/PPPPPPPP/RNBQKB1R w KQkq e6 0 2', after_pawn.to_fen
  end

  def test_placement_matches_the_fen
    [TestSupport::START_FEN, KIWIPETE, '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1'].each do |fen|
      assert_equal fen.split.first, position(fen).placement
    end
  end

  def test_accepts_legal_positions_and_moves
    assert_nil Rules.check!(TestSupport::START_FEN, %w[e2e4 e7e5 g1f3 b8c6 f1c4 g8f6 e1g1])
    assert_nil Rules.check!('4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2', %w[e5d6])
    assert_nil Rules.check!('4k3/1P6/8/8/8/8/8/4K3 w - - 0 1', %w[b7b8n])
  end

  def test_rejects_illegal_moves
    {
      [TestSupport::START_FEN, %w[e2e5]] => 'Illegal move e2e5 (moves[0])',
      [TestSupport::START_FEN, %w[e2e4 e2e4]] => 'Illegal move e2e4 (moves[1])',
      ['4k3/1P6/8/8/8/8/8/4K3 w - - 0 1', %w[b7b8]] => 'Illegal move b7b8 (moves[0])',
      [TestSupport::START_FEN, %w[e2e4q]] => 'Illegal move e2e4q (moves[0])',
      # The en passant capture would expose the king along the rank.
      ['8/8/8/KPp4r/8/8/8/4k3 w - c6 0 2', %w[b5c6]] => 'Illegal move b5c6 (moves[0])'
    }.each do |(fen, moves), message|
      error = assert_raises(Rules::IllegalInput) { Rules.check!(fen, moves) }

      assert_equal message, error.message
    end
  end

  def test_castling_needs_rights_a_clear_path_and_no_attacked_squares
    assert Rules::Moves.legal?(position(KIWIPETE), 'e1c1')
    refute Rules::Moves.legal?(position(KIWIPETE.sub('KQkq', 'Kkq')), 'e1c1'), 'without the right'
    refute Rules::Moves.legal?(position('r3k2r/8/8/8/8/8/8/R2QK2R w KQkq - 0 1'), 'e1c1'), 'path blocked'
    refute Rules::Moves.legal?(position('r3k2r/8/8/8/8/8/5r2/R3K2R w KQkq - 0 1'), 'e1g1'), 'through check'
    refute Rules::Moves.legal?(position('r3k2r/8/8/8/8/8/4r3/R3K2R w KQkq - 0 1'), 'e1g1'), 'out of check'
  end

  def test_moving_or_losing_a_rook_or_king_loses_castling_rights
    start = position('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1')

    assert_equal 'Qkq', start.after(Rules.square('h1'), Rules.square('h5')).castling
    assert_equal 'kq', start.after(Rules.square('e1'), Rules.square('e2')).castling
    assert_equal 'Kk', start.after(Rules.square('a1'), Rules.square('a8')).castling
  end

  def test_rejects_positions_stockfish_cannot_take
    {
      '8/8/8/3kK3/8/8/8/8 w - - 0 1' => 'the side not to move is in check',
      '4k3/8/8/8/8/8/4R3/4K3 w - - 0 1' => 'the side not to move is in check',
      '4k3/8/3N4/1B6/8/8/8/4RK2 b - - 0 1' => 'more than two pieces give check',
      'P3k3/8/8/8/8/8/8/4K3 w - - 0 1' => 'a pawn is on the first or last rank',
      'QQQQkQQQ/QQQQQQQQ/QQQQ4/8/8/8/8/4K3 w - - 0 1' => 'White has more pieces than a game can produce',
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKQNR w KQkq - 0 1' => 'White has more pieces than a game can produce',
      '4k3/8/8/8/8/8/8/4K3 w KQkq - 0 1' => 'castling right K needs the king and rook on their starting squares',
      'r3k1r1/8/8/8/8/8/8/R3K2R w KQkq - 0 1' => 'castling right k needs the king and rook on their starting squares',
      '4k3/8/8/8/8/8/8/4K3 w - e6 0 1' => 'en passant square e6 does not follow a double pawn step',
      '4k3/8/8/4p3/8/8/8/4K3 w - e3 0 1' => 'en passant square e3 does not follow a double pawn step'
    }.each do |fen, reason|
      error = assert_raises(Rules::IllegalInput, fen) { Rules.check!(fen, []) }

      assert_equal "Illegal position: #{reason}", error.message
    end
  end

  def test_accepts_an_en_passant_square_no_pawn_can_use
    # FENs written PGN-style record the square after every double step.
    assert_nil Rules.check!('rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1', [])
  end
end
