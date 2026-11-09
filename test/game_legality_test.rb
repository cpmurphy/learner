# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/pgn_reader'
require_relative '../lib/game_legality'

class GameLegalityTest < Minitest::Test
  def problem(movetext, tags = '')
    game = PGNReader.new.read("#{tags}[Result \"*\"]\n\n#{movetext} *\n").first
    GameLegality.problem(game)
  end

  def test_accepts_legal_games
    assert_nil problem('1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O b5 6. Bb3 d6')
    assert_nil problem('1. e4 d5 2. exd5 Qxd5 3. Nc3 Qa5 4. d4 c6 5. Bd2 Bf5 6. Qe2 Nd7 7. O-O-O')
    assert_nil problem('1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7#')
  end

  def test_accepts_every_game_in_the_test_data
    Dir[File.expand_path('data/*.pgn', __dir__)].each do |file|
      PGNReader.new.read(File.read(file)).each do |game|
        assert_nil GameLegality.problem(game), File.basename(file)
      end
    end
  end

  def test_rejects_a_move_the_piece_cannot_make
    assert_equal 'Move 2. Ke3 is not legal: that piece cannot move there.', problem('1. e4 e5 2. Ke3')
  end

  def test_rejects_moving_into_check
    assert_match(/4\.\.\. Ke7 is not legal: it leaves the king in check/,
                 problem('1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7# Ke7'))
  end

  def test_rejects_ignoring_a_check
    assert_match(/leaves the king in check/, problem('1. e4 f5 2. Qh5+ a6'))
  end

  def test_rejects_castling_through_or_out_of_check
    assert_match(/castle out of or through check/, problem('1. g3 b6 2. Bg2 Ba6 3. Nf3 e6 4. e4 c6 5. O-O'))
    # Qe4+ checks along the e-file; g1 and f1 are safe, so only the check matters.
    assert_match(/castle out of or through check/, problem('1. e4 d5 2. exd5 Qxd5 3. Nf3 Nf6 4. Bc4 Qe4+ 5. O-O'))
  end

  def test_rejects_null_moves
    assert_match(/null moves are not supported/, problem('1. e4 -- 2. d4'))
  end

  def test_rejects_a_pawn_reaching_the_last_rank_without_promoting
    assert_match(/not legal/, problem('1. e4 d5 2. exd5 c6 3. dxc6 Qd7 4. cxb7 Kd8 5. b8'))
  end

  def test_rejects_a_set_up_starting_position
    assert_equal 'The game must start from the standard starting position.',
                 problem('1. Kd2', "[FEN \"4k3/8/8/8/8/8/8/4K3 w - - 0 1\"]\n[SetUp \"1\"]\n")
  end
end
