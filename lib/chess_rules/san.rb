# frozen_string_literal: true

require_relative 'moves'

module ChessRules
  # Reads and writes Standard Algebraic Notation (SAN), the notation of PGN
  # files: "e4", "Nbd7", "exd6", "e8=Q", "O-O".
  #
  # Unlike the rest of ChessRules this is not shared with stockfish-pool, which
  # only takes UCI. It belongs in the shared gem once there is one.
  module San
    MOVE = /\A(?<piece>[KQRBN])?(?<file>[a-h])?(?<rank>[1-8])?x?(?<to>[a-h][1-8])(?:=?(?<promotion>[QRBN]))?\z/
    CASTLING = { 'O-O' => { 'w' => 'e1g1', 'b' => 'e8g8' }, 'O-O-O' => { 'w' => 'e1c1', 'b' => 'e8c8' } }.freeze
    # Check and mate marks, and annotation glyphs such as "!?".
    MARKS = /[+#!?]+\z/
    UCI = /\A[a-h][1-8][a-h][1-8][qrbn]?\z/

    module_function

    # The UCI move +san+ names in +position+. Raises IllegalInput, saying why,
    # unless exactly one legal move matches. A capture mark ("x") is optional,
    # and check and mate marks are ignored.
    def parse(position, san)
      notation = san.to_s.sub(MARKS, '')
      notation = notation.tr('0', 'O') if notation.match?(/\A0-0(-0)?\z/)
      return castle(position, notation) if CASTLING.key?(notation)

      match = MOVE.match(notation) or raise IllegalInput, "#{san} is not a move"
      only_legal_match(position, match)
    end

    # +uci+ (a legal move in +position+) in SAN. With +marks+, a check or mate
    # mark is appended.
    def write(position, uci, marks: true)
      raise IllegalInput, "Illegal move #{uci}" unless uci.is_a?(String) && UCI.match?(uci) &&
                                                       Moves.legal?(position, uci)

      from, to, promotion = squares(uci)
      san = castling_name(position, from, to) || move_name(position, from, to, promotion)
      marks ? san + mark(position.after(from, to, promotion)) : san
    end

    def squares(uci)
      [ChessRules.square(uci[0, 2]), ChessRules.square(uci[2, 2]), uci[4]]
    end

    # --- Reading ---

    def only_legal_match(position, match)
      shaped = Moves.pseudo_legal_moves(position).select { |uci| same_piece_and_square?(position, uci, match) }
      candidates = shaped.select { |uci| uci[4] == match[:promotion]&.downcase }
      legal = candidates.select { |uci| Moves.legal?(position, uci) }
      return legal.first if legal.size == 1

      raise IllegalInput, refusal(legal, candidates, shaped, match)
    end

    def refusal(legal, candidates, shaped, match)
      return 'the move is ambiguous' if legal.size > 1
      return 'it leaves the king in check' if candidates.any?
      return 'a pawn reaching the last rank must promote' if shaped.any? && match[:promotion].nil?
      return 'only a pawn reaching the last rank can promote' if shaped.any?

      'that piece cannot move there'
    end

    # The moving piece, target square and any file or rank hint match. A king
    # moving two squares is castling, which SAN writes as O-O, so it never matches.
    def same_piece_and_square?(position, uci, match)
      from, to, = squares(uci)
      piece = position[from].upcase
      return false if piece == 'K' && (to - from).abs == 2

      piece == (match[:piece] || 'P') && ChessRules.square_name(to) == match[:to] && hints_match?(uci, match)
    end

    # "Nbd7" names the knight on the b-file, "R1e2" the rook on the first rank.
    def hints_match?(uci, match)
      (match[:file].nil? || uci[0] == match[:file]) && (match[:rank].nil? || uci[1] == match[:rank])
    end

    def castle(position, notation)
      uci = CASTLING.fetch(notation).fetch(position.side)
      return uci if Moves.legal?(position, uci)

      raise IllegalInput, castling_refusal(position, uci)
    end

    def castling_refusal(position, uci)
      from, to, = squares(uci)
      right, rook, empty, = Moves::CASTLES.fetch([from, to])
      king = position.side == 'w' ? 'K' : 'k'
      unless position[from] == king && Moves.castling_right?(position, right, rook)
        return 'castling is no longer allowed'
      end
      return 'pieces stand between the king and the rook' if empty.any? { |square| position[square] }

      'the king cannot castle out of, through or into check'
    end

    # --- Writing ---

    def castling_name(position, from, to)
      return unless position[from].upcase == 'K' && (to - from).abs == 2

      to > from ? 'O-O' : 'O-O-O'
    end

    def move_name(position, from, to, promotion)
      piece = position[from].upcase
      capture = !position[to].nil? || (piece == 'P' && to == position.en_passant)
      target = ChessRules.square_name(to)
      if piece == 'P'
        "#{"#{ChessRules.square_name(from)[0]}x" if capture}#{target}#{"=#{promotion.upcase}" if promotion}"
      else
        "#{piece}#{disambiguation(position, from, to)}#{'x' if capture}#{target}"
      end
    end

    # The file, else the rank, else both, of the moving piece when another
    # piece of the same kind could also legally move to +to+.
    def disambiguation(position, from, to)
      rivals = rivals(position, from, to)
      return '' if rivals.empty?

      name = ChessRules.square_name(from)
      return name[0] if rivals.none? { |square| square % 8 == from % 8 }
      return name[1] if rivals.none? { |square| square / 8 == from / 8 }

      name
    end

    def rivals(position, from, to)
      (0..63).select do |square|
        square != from && position[square] == position[from] && Moves.legal?(position, Moves.uci(square, to))
      end
    end

    def mark(after)
      return '' unless after.in_check?(after.side)

      Moves.pseudo_legal_moves(after).any? { |uci| Moves.legal?(after, uci) } ? '+' : '#'
    end
  end
end
