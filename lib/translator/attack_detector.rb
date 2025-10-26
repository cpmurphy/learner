# frozen_string_literal: true

module Translator
  # Detects attacks and checks in chess positions
  class AttackDetector
    def initialize(board, move_validator)
      @board = board
      @move_validator = move_validator
    end

    def moves_into_check?(from, to, piece)
      # Save the current state
      original_to_piece = @board[to]
      original_from_piece = @board[from]

      # Make the move
      @board[to] = original_from_piece
      @board.delete(from)

      # Find the king's position after the move
      king_square = if piece.upcase == 'K'
                      to # If moving the king, use the destination square
                    else
                      @board.find_king # Otherwise find the king's current position
                    end

      # Check if any opponent's piece can attack the king
      result = opponent_attacks_square?(king_square)

      # Restore board state
      @board[from] = original_from_piece
      if original_to_piece
        @board[to] = original_to_piece
      else
        @board.delete(to)
      end

      result
    end

    def opponent_attacks_square?(square)
      find_opposing_pieces(square).any? { |from_square, piece| attacks_square?(from_square, piece, square) }
    end

    private

    def find_opposing_pieces(_square)
      pattern = @board.current_player == :white ? /[pnbrqk]/ : /[PNBRQK]/
      @board.squares.select { |_sq, piece| piece =~ pattern }
    end

    def attacks_square?(from_square, piece, target_square)
      return false if from_square == target_square

      piece_can_attack?(piece, from_square, target_square)
    end

    def piece_can_attack?(piece, from_square, target_square)
      case piece.upcase
      when 'P' then pawn_attacks_square?(from_square, target_square)
      when 'N' then @move_validator.valid_knight_move?(from_square, target_square)
      when 'B' then @move_validator.valid_bishop_move?(from_square, target_square)
      when 'R' then @move_validator.valid_rook_move?(from_square, target_square)
      when 'Q' then @move_validator.valid_queen_move?(from_square, target_square)
      when 'K' then @move_validator.valid_king_move?(from_square, target_square)
      end
    end

    def pawn_attacks_square?(from, to)
      from_file, from_rank = from.chars
      to_file, to_rank = to.chars

      file_diff = (from_file.ord - to_file.ord).abs
      rank_diff = to_rank.to_i - from_rank.to_i

      direction = @board[from] =~ /[A-Z]/ ? 1 : -1 # White moves up, black moves down

      file_diff == 1 && rank_diff == direction
    end
  end
end
