# frozen_string_literal: true

module Translator
  # Manages castling rights and validation
  class Castling
    def initialize(board)
      @board = board
    end

    def generate_castling_rights_for_fen
      if any_castling_moves_allowed?
        @board.white_castle_moves_allowed + @board.black_castle_moves_allowed
      else
        '-'
      end
    end

    def valid_castling?(from, to)
      rank = @board.current_player == :white ? '1' : '8'
      is_kingside = to[0] > from[0]

      return false unless king_in_correct_position?(from, rank)
      return false unless rook_in_correct_position?(is_kingside, rank)
      return false unless path_clear_for_castling?(is_kingside, rank)

      true
    end

    def update_castling_status(piece, from)
      case piece.upcase
      when 'K'
        remove_all_castling_rights
      when 'R'
        remove_castling_rights_for_rook_move(from)
      end
    end

    def remove_all_castling_rights
      if @board.current_player == :white
        @board.white_castle_moves_allowed = ''
      else
        @board.black_castle_moves_allowed = ''
      end
    end

    def any_castling_moves_allowed?
      @board.white_castle_moves_allowed.length.positive? || @board.black_castle_moves_allowed.length.positive?
    end

    private

    def king_in_correct_position?(from, rank)
      king_file = 'e'
      expected_square = "#{king_file}#{rank}"
      from == expected_square && @board[expected_square]&.upcase == 'K'
    end

    def rook_in_correct_position?(is_kingside, rank)
      rook_file = is_kingside ? 'h' : 'a'
      rook_square = "#{rook_file}#{rank}"
      @board[rook_square]&.upcase == 'R'
    end

    def path_clear_for_castling?(is_kingside, rank)
      path = if is_kingside
               ('f'...'h').map { |file| "#{file}#{rank}" }
             else
               ('b'..'d').map { |file| "#{file}#{rank}" }
             end

      path.none? { |square| @board[square] }
    end

    def remove_castling_rights_for_rook_move(from)
      castling_effect = {
        'h1' => { side: :white, keep: 'Q', rights: @board.white_castle_moves_allowed },
        'a1' => { side: :white, keep: 'K', rights: @board.white_castle_moves_allowed },
        'h8' => { side: :black, keep: 'q', rights: @board.black_castle_moves_allowed },
        'a8' => { side: :black, keep: 'k', rights: @board.black_castle_moves_allowed }
      }[from]

      return unless castling_effect && castling_effect[:rights]

      if castling_effect[:side] == :white
        @board.white_castle_moves_allowed = castling_effect[:rights].length > 1 ? castling_effect[:keep] : ''
      else
        @board.black_castle_moves_allowed = castling_effect[:rights].length > 1 ? castling_effect[:keep] : ''
      end
    end
  end
end
