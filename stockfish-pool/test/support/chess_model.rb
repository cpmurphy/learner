# frozen_string_literal: true

# A small chess rules model for the property tests. The tests use it as an
# oracle that does not depend on Stockfish: it builds positions, plays moves,
# writes FENs and lists legal moves. Castling is not modelled; every position
# the tests build has no castling rights.
module ChessModel
  KNIGHT_STEPS = [[1, 2], [2, 1], [-1, 2], [-2, 1], [1, -2], [2, -1], [-1, -2], [-2, -1]].freeze
  KING_STEPS = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]].freeze
  ROOK_DIRECTIONS = [[1, 0], [-1, 0], [0, 1], [0, -1]].freeze
  BISHOP_DIRECTIONS = [[1, 1], [1, -1], [-1, 1], [-1, -1]].freeze
  PROMOTIONS = %w[q r b n].freeze

  module_function

  # Squares are [file, rank] pairs, both 0..7: [0, 0] is a1.
  def on_board?(square)
    square.all? { |coordinate| coordinate.between?(0, 7) }
  end

  def square_name(square)
    "#{'abcdefgh'[square[0]]}#{square[1] + 1}"
  end

  def parse_square(name)
    [name.ord - 'a'.ord, name[1].to_i - 1]
  end

  def color_of(piece)
    piece == piece.upcase ? 'w' : 'b'
  end

  def opponent(color)
    color == 'w' ? 'b' : 'w'
  end

  def piece_for(color, type)
    color == 'w' ? type.upcase : type.downcase
  end

  def add(square, step)
    [square[0] + step[0], square[1] + step[1]]
  end

  def flip_square(square)
    [square[0], 7 - square[1]]
  end

  def flip_move(uci)
    from, to = [uci[0, 2], uci[2, 2]].map { |name| square_name(flip_square(parse_square(name))) }
    "#{from}#{to}#{uci[4]}"
  end

  # One chess position. #play returns a new Position; nothing changes one in place.
  class Position
    attr_reader :board, :side, :ep, :halfmove, :fullmove

    def self.from_fen(fen)
      placement, side, _castling, ep, halfmove, fullmove = fen.split
      board = {}
      placement.split('/').each_with_index do |row, index|
        file = 0
        row.each_char do |char|
          if char.match?(/\d/)
            file += char.to_i
          else
            board[[file, 7 - index]] = char
            file += 1
          end
        end
      end
      new(board, side: side, en_passant: ep == '-' ? nil : ChessModel.parse_square(ep),
                 halfmove: halfmove.to_i, fullmove: fullmove.to_i)
    end

    def initialize(board, side:, en_passant: nil, halfmove: 0, fullmove: 1)
      @board = board.dup.freeze
      @side = side
      @ep = en_passant
      @halfmove = halfmove
      @fullmove = fullmove
    end

    def to_fen
      rows = 7.downto(0).map do |rank|
        (0..7).map { |file| @board[[file, rank]] || '1' }.join.gsub(/1+/) { |run| run.length.to_s }
      end
      ep = @ep ? ChessModel.square_name(@ep) : '-'
      "#{rows.join('/')} #{@side} - #{ep} #{@halfmove} #{@fullmove}"
    end

    alias to_s to_fen

    def ==(other)
      other.is_a?(Position) && to_fen == other.to_fen
    end

    def king_square(color)
      king = ChessModel.piece_for(color, 'k')
      @board.key(king)
    end

    def attacked?(square, attacker)
      pawn_attacker?(square, attacker) ||
        step_attacker?(square, attacker, KNIGHT_STEPS, 'n') ||
        step_attacker?(square, attacker, KING_STEPS, 'k') ||
        slider_attacker?(square, attacker, ROOK_DIRECTIONS, %w[r q]) ||
        slider_attacker?(square, attacker, BISHOP_DIRECTIONS, %w[b q])
    end

    def checkers(color)
      king = king_square(color)
      attacker = ChessModel.opponent(color)
      @board.keys.select do |square|
        piece = @board[square]
        ChessModel.color_of(piece) == attacker && attacks_from(square).include?(king)
      end
    end

    def in_check?(color = @side)
      attacked?(king_square(color), ChessModel.opponent(color))
    end

    # A position Stockfish can be given: one king each, no pawns on the first or
    # last rank, the side not to move not in check, and at most two checkers.
    def well_formed?
      %w[K k].all? { |king| @board.values.count(king) == 1 } &&
        @board.none? { |square, piece| piece.downcase == 'p' && [0, 7].include?(square[1]) } &&
        !in_check?(ChessModel.opponent(@side)) &&
        checkers(@side).size <= 2
    end

    def legal_moves
      @legal_moves ||= pseudo_moves.reject { |move| play(move).in_check?(@side) }.freeze
    end

    def checkmate?
      legal_moves.empty? && in_check?
    end

    def stalemate?
      legal_moves.empty? && !in_check?
    end

    # Plays a UCI move without checking that it is legal.
    def play(uci)
      from = ChessModel.parse_square(uci[0, 2])
      to = ChessModel.parse_square(uci[2, 2])
      pawn = @board.fetch(from).downcase == 'p'
      resets_clock = pawn || @board.key?(to)
      Position.new(board_after(from, to, uci[4]),
                   side: ChessModel.opponent(@side),
                   en_passant: pawn && (to[1] - from[1]).abs == 2 ? [from[0], (from[1] + to[1]) / 2] : nil,
                   halfmove: resets_clock ? 0 : @halfmove + 1,
                   fullmove: @side == 'b' ? @fullmove + 1 : @fullmove)
    end

    # The same position with colours swapped and the board mirrored top to bottom.
    def flip
      board = @board.to_h do |square, piece|
        [ChessModel.flip_square(square), piece == piece.upcase ? piece.downcase : piece.upcase]
      end
      Position.new(board, side: ChessModel.opponent(@side), en_passant: @ep && ChessModel.flip_square(@ep),
                          halfmove: @halfmove, fullmove: @fullmove)
    end

    # Squares the piece on +square+ attacks (pawns: diagonals only).
    def attacks_from(square)
      piece = @board.fetch(square)
      case piece.downcase
      when 'p' then pawn_captures(square, ChessModel.color_of(piece))
      when 'n' then steps(square, KNIGHT_STEPS)
      when 'k' then steps(square, KING_STEPS)
      when 'b' then slides(square, BISHOP_DIRECTIONS)
      when 'r' then slides(square, ROOK_DIRECTIONS)
      when 'q' then slides(square, ROOK_DIRECTIONS + BISHOP_DIRECTIONS)
      end
    end

    private

    def pseudo_moves
      @board.flat_map do |square, piece|
        next [] unless ChessModel.color_of(piece) == @side

        if piece.downcase == 'p'
          pawn_moves(square)
        else
          attacks_from(square).reject { |target| own?(target) }.map { |target| uci(square, target) }
        end
      end
    end

    def board_after(from, to, promotion)
      board = @board.dup
      piece = board.delete(from)
      # En passant: the captured pawn is beside the capturing one, not on +to+.
      board.delete([to[0], from[1]]) if piece.downcase == 'p' && to == @ep
      board[to] = promotion ? ChessModel.piece_for(@side, promotion) : piece
      board
    end

    def pawn_moves(square)
      targets = pawn_pushes(square) + pawn_captures(square, @side).select { |target| enemy?(target) || target == @ep }
      targets.flat_map do |target|
        promotions = [0, 7].include?(target[1]) ? PROMOTIONS : [nil]
        promotions.map { |type| uci(square, target, type) }
      end
    end

    def pawn_pushes(square)
      forward = @side == 'w' ? 1 : -1
      one = ChessModel.add(square, [0, forward])
      return [] if !ChessModel.on_board?(one) || @board.key?(one)

      two = ChessModel.add(one, [0, forward])
      start_rank = @side == 'w' ? 1 : 6
      square[1] == start_rank && !@board.key?(two) ? [one, two] : [one]
    end

    def pawn_captures(square, color)
      forward = color == 'w' ? 1 : -1
      [[-1, forward], [1, forward]].map { |step| ChessModel.add(square, step) }.select { |s| ChessModel.on_board?(s) }
    end

    def steps(square, offsets)
      offsets.map { |step| ChessModel.add(square, step) }.select { |target| ChessModel.on_board?(target) }
    end

    def slides(square, directions)
      directions.flat_map do |step|
        ray = []
        target = ChessModel.add(square, step)
        while ChessModel.on_board?(target)
          ray << target
          break if @board.key?(target)

          target = ChessModel.add(target, step)
        end
        ray
      end
    end

    def pawn_attacker?(square, attacker)
      back = attacker == 'w' ? -1 : 1
      [[-1, back], [1, back]].any? { |step| @board[ChessModel.add(square, step)] == ChessModel.piece_for(attacker, 'p') }
    end

    def step_attacker?(square, attacker, offsets, type)
      piece = ChessModel.piece_for(attacker, type)
      offsets.any? { |step| @board[ChessModel.add(square, step)] == piece }
    end

    def slider_attacker?(square, attacker, directions, types)
      pieces = types.map { |type| ChessModel.piece_for(attacker, type) }
      directions.any? do |step|
        target = ChessModel.add(square, step)
        target = ChessModel.add(target, step) while ChessModel.on_board?(target) && !@board.key?(target)
        pieces.include?(@board[target])
      end
    end

    def own?(square)
      @board.key?(square) && ChessModel.color_of(@board[square]) == @side
    end

    def enemy?(square)
      @board.key?(square) && ChessModel.color_of(@board[square]) != @side
    end

    def uci(from, to, promotion = nil)
      "#{ChessModel.square_name(from)}#{ChessModel.square_name(to)}#{promotion}"
    end
  end
end
