# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../lib/translator/board'

module Translator
  class BoardTest < Minitest::Test
    def setup
      @board = Board.new
      @board.clear # Start with an empty board for controlled testing
    end

    def test_opponent_attacks_square_by_pawn
      # Set up a white pawn that can attack a square
      @board['e4'] = 'P'
      @board.current_player = :black

      # Test diagonal attacks
      assert @board.opponent_attacks_square?('d5'), 'White pawn should attack d5'
      assert @board.opponent_attacks_square?('f5'), 'White pawn should attack f5'
    end

    def test_non_attacked_squares_by_pawn
      # Test non-attacked squares
      refute @board.opponent_attacks_square?('e5'), 'White pawn should not attack directly forward'
      refute @board.opponent_attacks_square?('d4'), 'White pawn should not attack same rank'
    end

    def test_opponent_attacks_square_by_knight
      # Set up a black knight
      @board['e4'] = 'n'
      @board.current_player = :white

      # Test three possible knight moves
      assert @board.opponent_attacks_square?('f6'), 'Knight should attack f6'
      assert @board.opponent_attacks_square?('c3'), 'Knight should attack c3'
      assert @board.opponent_attacks_square?('g3'), 'Knight should attack g3'
    end

    # Test non-attacked square
    def test_non_attacked_squares_by_knight
      refute @board.opponent_attacks_square?('e5'), 'Knight should not attack e5'
    end

    def test_opponent_attacks_square_by_bishop
      # Set up a white bishop
      @board['c1'] = 'B'
      @board.current_player = :black

      # Test diagonal attacks
      assert @board.opponent_attacks_square?('a3'), 'Bishop should attack a3'
      assert @board.opponent_attacks_square?('f4'), 'Bishop should attack f4'

      # Test blocked attacks
      @board['d2'] = 'P'

      refute @board.opponent_attacks_square?('f4'), 'Bishop should not attack through pieces'
    end

    def test_opponent_attacks_square_by_rook
      # Set up a black rook
      @board['a8'] = 'r'
      @board.current_player = :white

      # Test horizontal and vertical attacks
      assert @board.opponent_attacks_square?('a1'), 'Rook should attack a1'
      assert @board.opponent_attacks_square?('h8'), 'Rook should attack h8'

      # Test blocked attacks
      @board['a4'] = 'p'

      refute @board.opponent_attacks_square?('a1'), 'Rook should not attack through pieces'
    end

    def test_opponent_attacks_square_by_queen
      # Set up a white queen
      @board['d1'] = 'Q'
      @board.current_player = :black

      # Test diagonal, horizontal, and vertical attacks
      assert @board.opponent_attacks_square?('d8'), 'Queen should attack vertically'
      assert @board.opponent_attacks_square?('h1'), 'Queen should attack horizontally'
      assert @board.opponent_attacks_square?('h5'), 'Queen should attack diagonally'
    end

    def test_non_attacked_squares_by_queen
      # Test blocked attacks
      @board['d4'] = 'P'

      refute @board.opponent_attacks_square?('d8'), 'Queen should not attack through pieces'
    end

    def test_moves_into_check_by_moving_piece
      # Set up a position where moving a piece exposes the king to check
      @board['e1'] = 'K'
      @board['e2'] = 'Q'
      @board['e8'] = 'r'
      @board.current_player = :white

      # Moving the queen should expose the king to check
      assert @board.moves_into_check?('e2', 'd3', 'Q'),
             'Moving queen should be detected as exposing king to check'

      # Moving the queen to block the check should be valid
      refute @board.moves_into_check?('e2', 'e3', 'Q'),
             'Moving queen to block check should be valid'
    end

    def test_moves_into_check_by_king_movement
      # Set up a position where the king would move into check
      @board['e1'] = 'K'
      @board['h2'] = 'r'
      @board.current_player = :white

      # King moving into attacked square
      assert @board.moves_into_check?('e1', 'e2', 'K'),
             'King moving into attacked square should be detected'

      # King moving to safe square
      refute @board.moves_into_check?('e1', 'f1', 'K'),
             'King moving to safe square should be valid'
    end

    def test_moves_into_check_capturing_attacking_piece
      # Set up a position where capturing an attacking piece prevents check
      @board['e1'] = 'K'
      @board['d2'] = 'Q'
      @board['h1'] = 'r'
      @board.current_player = :white

      # Capturing the attacking piece should be valid
      refute @board.moves_into_check?('d2', 'h1', 'Q'),
             'Capturing attacking piece should be valid'
    end

    def test_board_state_restored_after_check_test
      # Set up initial position
      @board['e1'] = 'K'
      @board['d2'] = 'Q'
      @board['h1'] = 'r'
      initial_state = @board.squares.dup

      # Perform check test
      @board.moves_into_check?('d2', 'c3', 'Q')

      # Verify board state is restored
      assert_equal initial_state, @board.squares,
                   'Board state should be restored after check test'
    end
  end
end
