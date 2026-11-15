# frozen_string_literal: true

require_relative 'position'

module ChessRules
  # Decides whether a UCI move (already shaped like one) is legal, and lists
  # the legal moves of a position.
  module Moves
    # King from and to => [castling right, rook square, squares that must be
    # empty, squares the king stands on or crosses, which must not be attacked].
    CASTLES = {
      [4, 6] => ['K', 7, [5, 6], [4, 5, 6]],
      [4, 2] => ['Q', 0, [1, 2, 3], [4, 3, 2]],
      [60, 62] => ['k', 63, [61, 62], [60, 61, 62]],
      [60, 58] => ['q', 56, [57, 58, 59], [60, 59, 58]]
    }.freeze

    PROMOTIONS = %w[q r b n].freeze

    module_function

    # Every legal move in +position+, in UCI.
    def legal_moves(position)
      pseudo_legal_moves(position).select { |uci| legal?(position, uci) }
    end

    # Moves that follow the pieces' movement rules (castling included) but may
    # leave the mover's king in check.
    def pseudo_legal_moves(position)
      (0..63).select { |square| own_piece?(position, square) }.flat_map do |from|
        targets(position, from).flat_map do |to|
          promotions(position, from, to).filter_map do |promotion|
            uci(from, to, promotion) if reachable?(position, from, to, promotion)
          end
        end
      end
    end

    # Squares a piece could move to, before checking its movement rules.
    def targets(position, from)
      candidates = position[from].downcase == 'p' ? pawn_targets(position, from) : (0..63).to_a
      candidates.select { |to| to != from && enterable?(position, to) }
    end

    def pawn_targets(position, from)
      forward = position.side == 'w' ? 1 : -1
      one = ChessRules.offset(from, 0, forward)
      [one, one && ChessRules.offset(one, 0, forward), *position.pawn_attacks(from, position.side)].compact
    end

    def promotions(position, from, to)
      position[from].downcase == 'p' && [0, 7].include?(to / 8) ? PROMOTIONS : [nil]
    end

    def uci(from, to, promotion = nil)
      "#{ChessRules.square_name(from)}#{ChessRules.square_name(to)}#{promotion}"
    end

    def legal?(position, uci)
      from = ChessRules.square(uci[0, 2])
      to = ChessRules.square(uci[2, 2])
      promotion = uci[4]
      return false unless own_piece?(position, from) && enterable?(position, to)
      return false unless reachable?(position, from, to, promotion)

      !position.after(from, to, promotion).in_check?(position.side)
    end

    def own_piece?(position, square)
      piece = position[square]
      !piece.nil? && ChessRules.color_of(piece) == position.side
    end

    # Empty, or an opponent's piece other than the king.
    def enterable?(position, square)
      piece = position[square]
      piece.nil? || (ChessRules.color_of(piece) != position.side && piece.downcase != 'k')
    end

    def reachable?(position, from, to, promotion)
      type = position[from].downcase
      return pawn_move?(position, from, to, promotion) if type == 'p'
      return false if promotion

      position.attacks?(from, to) || (type == 'k' && castle?(position, from, to))
    end

    # A pawn reaching the last rank must promote, and only then may it.
    def pawn_move?(position, from, to, promotion)
      forward = position.side == 'w' ? 1 : -1
      last_rank = forward == 1 ? 7 : 0
      return false unless (to / 8 == last_rank) == !promotion.nil?

      pawn_push?(position, from, to, forward) || pawn_capture?(position, from, to)
    end

    def pawn_push?(position, from, to, forward)
      one = ChessRules.offset(from, 0, forward)
      return false if one.nil? || position[one]
      return true if to == one

      start_rank = forward == 1 ? 1 : 6
      from / 8 == start_rank && to == ChessRules.offset(one, 0, forward) && position[to].nil?
    end

    def pawn_capture?(position, from, to)
      position.pawn_attacks(from, position.side).include?(to) && (!position[to].nil? || to == position.en_passant)
    end

    def castle?(position, from, to)
      right, rook, empty, crossed = CASTLES[[from, to]]
      return false unless right && castling_right?(position, right, rook)

      empty.none? { |square| position[square] } &&
        crossed.none? { |square| position.attacked?(square, position.opponent) }
    end

    def castling_right?(position, right, rook)
      ChessRules.color_of(right) == position.side && position.castling.include?(right) &&
        position[rook] == (position.side == 'w' ? 'R' : 'r')
    end
  end
end
