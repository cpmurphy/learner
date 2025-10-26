# frozen_string_literal: true

require_relative 'move_validator'
require_relative 'castling'
require_relative 'attack_detector'

module Translator
  # Manages the chess board state and basic board operations
  class Board
    STARTING_POSITION = {
      'a1' => 'R', 'b1' => 'N', 'c1' => 'B', 'd1' => 'Q', 'e1' => 'K', 'f1' => 'B', 'g1' => 'N', 'h1' => 'R',
      'a2' => 'P', 'b2' => 'P', 'c2' => 'P', 'd2' => 'P', 'e2' => 'P', 'f2' => 'P', 'g2' => 'P', 'h2' => 'P',
      'a7' => 'p', 'b7' => 'p', 'c7' => 'p', 'd7' => 'p', 'e7' => 'p', 'f7' => 'p', 'g7' => 'p', 'h7' => 'p',
      'a8' => 'r', 'b8' => 'n', 'c8' => 'b', 'd8' => 'q', 'e8' => 'k', 'f8' => 'b', 'g8' => 'n', 'h8' => 'r'
    }.freeze

    def initialize
      @squares = STARTING_POSITION.dup
      @current_player = :white
      @last_move = nil
      @white_castle_moves_allowed = 'KQ'
      @black_castle_moves_allowed = 'kq'
      @en_passant_target = '-'

      @move_validator = MoveValidator.new(self)
      @castling = Castling.new(self)
      @attack_detector = AttackDetector.new(self, @move_validator)
    end

    attr_accessor :squares, :current_player, :last_move, :white_castle_moves_allowed, :black_castle_moves_allowed,
                  :en_passant_target

    def [](square)
      @squares[square]
    end

    def []=(square, piece)
      @squares[square] = piece
    end

    def delete(square)
      @squares.delete(square)
    end

    def switch_player
      @current_player = @current_player == :white ? :black : :white
    end

    def find_king
      @squares.each do |square, piece|
        return square if piece == (current_player == :white ? 'K' : 'k')
      end
      nil
    end

    def find_piece(piece)
      @squares.select { |_square, p| p == piece }
    end

    def clear
      @squares.clear
    end

    def moves_into_check?(from, to, piece)
      @attack_detector.moves_into_check?(from, to, piece)
    end

    def opponent_attacks_square?(square)
      @attack_detector.opponent_attacks_square?(square)
    end

    def valid_move?(from, to, piece)
      @move_validator.valid_move?(from, to, piece)
    end

    def generate_castling_rights_for_fen
      @castling.generate_castling_rights_for_fen
    end

    def valid_castling?(from, to)
      @castling.valid_castling?(from, to)
    end

    def update_castling_status(piece, from)
      @castling.update_castling_status(piece, from)
    end

    def remove_all_castling_rights
      @castling.remove_all_castling_rights
    end

    def any_castling_moves_allowed?
      @castling.any_castling_moves_allowed?
    end

    def castling_rights=(castling)
      @white_castle_moves_allowed = castling.include?('K') ? 'K' : ''
      @white_castle_moves_allowed += castling.include?('Q') ? 'Q' : ''
      @black_castle_moves_allowed = castling.include?('k') ? 'k' : ''
      @black_castle_moves_allowed += castling.include?('q') ? 'q' : ''
    end
  end
end
