# frozen_string_literal: true

require_relative 'position'

module StockfishPool
  module Rules
    # Finds what makes a position unsafe or impossible to search. Stockfish
    # assumes positions are legal: given adjacent kings, the side not to move
    # in check, castling rights without the rook, or more material than a
    # game can produce, it may crash or overrun its move list.
    module PositionCheck
      STARTING_COUNTS = { 'q' => 1, 'r' => 2, 'b' => 2, 'n' => 2 }.freeze
      # Castling right => [king square, king, rook square, rook].
      HOME_SQUARES = {
        'K' => [4, 'K', 7, 'R'], 'Q' => [4, 'K', 0, 'R'],
        'k' => [60, 'k', 63, 'r'], 'q' => [60, 'k', 56, 'r']
      }.freeze
      COLOR_NAMES = { 'w' => 'White', 'b' => 'Black' }.freeze

      module_function

      # The reason +position+ is refused, or nil if it is fine. One king of
      # each colour is already guaranteed by InputValidator.
      def problem(position)
        return 'a pawn is on the first or last rank' if back_rank_pawn?(position)

        material = COLOR_NAMES.keys.filter_map { |color| material_problem(position, color) }.first
        material || check_problem(position) || castling_problem(position) || en_passant_problem(position)
      end

      def back_rank_pawn?(position)
        (0..7).chain(56..63).any? { |square| position[square]&.downcase == 'p' }
      end

      # No more than 16 pieces, 8 pawns, and one promoted piece per missing pawn.
      def material_problem(position, color)
        counts = position.pieces(color).map(&:downcase).tally
        pawns = counts.fetch('p', 0)
        promoted = STARTING_COUNTS.sum { |type, start| [counts.fetch(type, 0) - start, 0].max }
        return unless counts.values.sum > 16 || pawns > 8 || promoted > 8 - pawns

        "#{COLOR_NAMES[color]} has more pieces than a game can produce"
      end

      def check_problem(position)
        return 'the side not to move is in check' if position.in_check?(position.opponent)

        king = position.king(position.side)
        'more than two pieces give check' if position.attackers(king, position.opponent).size > 2
      end

      def castling_problem(position)
        right = position.castling.chars.find do |letter|
          king_square, king, rook_square, rook = HOME_SQUARES.fetch(letter)
          position[king_square] != king || position[rook_square] != rook
        end
        "castling right #{right} needs the king and rook on their starting squares" if right
      end

      # An en passant square must be just behind a pawn of the side not to
      # move that could have arrived by a double step: on the right rank, with
      # the square it passed and the square it came from empty.
      def en_passant_problem(position)
        square = position.en_passant
        return if square.nil? || behind_double_step?(position, square)

        "en passant square #{Rules.square_name(square)} does not follow a double pawn step"
      end

      def behind_double_step?(position, square)
        forward = position.side == 'w' ? 1 : -1
        return false unless square / 8 == (forward == 1 ? 5 : 2)

        pushed_pawn = position[Rules.offset(square, 0, -forward)]
        origin = Rules.offset(square, 0, forward)
        pushed_pawn == (forward == 1 ? 'p' : 'P') && position[square].nil? && position[origin].nil?
      end
    end
  end
end
