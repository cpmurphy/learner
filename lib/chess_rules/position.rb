# frozen_string_literal: true

# Just enough chess to keep input Stockfish cannot handle away from it:
# positions it may crash on, and moves it would silently ignore (it stops
# reading "position ... moves" at the first move it cannot play). Standard
# chess only; the engines never run in Chess960 mode.
module ChessRules
  # Squares are 0..63: a1 is 0, h1 is 7, a8 is 56.
  KNIGHT_STEPS = [[1, 2], [2, 1], [-1, 2], [-2, 1], [1, -2], [2, -1], [-1, -2], [-2, -1]].freeze
  KING_STEPS = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]].freeze
  ROOK_DIRECTIONS = [[1, 0], [-1, 0], [0, 1], [0, -1]].freeze
  BISHOP_DIRECTIONS = [[1, 1], [1, -1], [-1, 1], [-1, -1]].freeze
  QUEEN_DIRECTIONS = (ROOK_DIRECTIONS + BISHOP_DIRECTIONS).freeze

  module_function

  def square(name)
    ((name.getbyte(1) - 49) * 8) + (name.getbyte(0) - 97)
  end

  def square_name(square)
    "#{(97 + (square % 8)).chr}#{(square / 8) + 1}"
  end

  def color_of(piece)
    piece == piece.upcase ? 'w' : 'b'
  end

  def opponent(color)
    color == 'w' ? 'b' : 'w'
  end

  # The square +file_step+ files and +rank_step+ ranks away, or nil off the board.
  def offset(square, file_step, rank_step)
    file = (square % 8) + file_step
    rank = (square / 8) + rank_step
    (rank * 8) + file if file.between?(0, 7) && rank.between?(0, 7)
  end

  # A position read from a FEN whose shape UciInputValidator has already
  # checked: the board, side to move, castling rights, en passant square and
  # move clocks. #after returns a new Position; nothing changes one in place.
  class Position
    CORNER_RIGHTS = { 0 => 'Q', 7 => 'K', 56 => 'q', 63 => 'k' }.freeze
    KING_RIGHTS = { 'K' => 'KQ', 'k' => 'kq' }.freeze

    attr_reader :side, :castling, :en_passant, :halfmove, :fullmove

    def self.from_fen(fen)
      placement, side, castling, en_passant, halfmove, fullmove = fen.split
      squares = []
      placement.split('/').reverse_each do |row|
        row.each_char { |char| char.match?(/\d/) ? squares.concat([nil] * char.to_i) : squares << char }
      end
      new(squares, side, castling.delete('-'), en_passant == '-' ? nil : ChessRules.square(en_passant),
          halfmove.to_i, fullmove.to_i)
    end

    # rubocop:disable Metrics/ParameterLists
    def initialize(squares, side, castling, en_passant, halfmove = 0, fullmove = 1)
      # rubocop:enable Metrics/ParameterLists
      @squares = squares.freeze
      @side = side
      @castling = castling
      @en_passant = en_passant
      @halfmove = halfmove
      @fullmove = fullmove
      freeze
    end

    def to_fen
      en_passant = @en_passant ? ChessRules.square_name(@en_passant) : '-'
      [placement, @side, @castling.empty? ? '-' : @castling, en_passant, @halfmove, @fullmove].join(' ')
    end

    def [](square)
      @squares[square]
    end

    # The piece-placement field of a FEN for this board.
    def placement
      @squares.each_slice(8).reverse_each.map do |rank|
        rank.map { |piece| piece || '1' }.join.gsub(/1+/) { |run| run.length.to_s }
      end.join('/')
    end

    def opponent
      ChessRules.opponent(@side)
    end

    def pieces(color)
      @squares.compact.select { |piece| ChessRules.color_of(piece) == color }
    end

    def king(color)
      @squares.index(color == 'w' ? 'K' : 'k')
    end

    # Squares holding a piece of +color+ that attacks +target+.
    def attackers(target, color)
      @squares.each_index.select do |from|
        piece = @squares[from]
        piece && ChessRules.color_of(piece) == color && attacks?(from, target)
      end
    end

    def attacked?(target, color)
      !attackers(target, color).empty?
    end

    def in_check?(color)
      attacked?(king(color), ChessRules.opponent(color))
    end

    # Whether the piece on +from+ attacks +target+ (for pawns, diagonally).
    def attacks?(from, target)
      piece = @squares[from]
      case piece.downcase
      when 'p' then pawn_attacks(from, ChessRules.color_of(piece)).include?(target)
      when 'n' then steps(from, KNIGHT_STEPS).include?(target)
      when 'k' then steps(from, KING_STEPS).include?(target)
      when 'b' then reaches?(from, target, BISHOP_DIRECTIONS)
      when 'r' then reaches?(from, target, ROOK_DIRECTIONS)
      else reaches?(from, target, QUEEN_DIRECTIONS)
      end
    end

    def pawn_attacks(from, color)
      forward = color == 'w' ? 1 : -1
      [ChessRules.offset(from, -1, forward), ChessRules.offset(from, 1, forward)].compact
    end

    # The position after a move, which must be pseudo-legal (see Moves).
    def after(from, to, promotion = nil)
      Position.new(squares_after(from, to, promotion), opponent, castling_after(from, to),
                   double_push?(from, to) ? (from + to) / 2 : nil,
                   halfmove_after(from, to), @side == 'b' ? @fullmove + 1 : @fullmove)
    end

    private

    def squares_after(from, to, promotion)
      squares = @squares.dup
      piece = squares[from]
      squares[from] = nil
      # En passant: the captured pawn is beside the capturing one, not on +to+.
      squares[(from / 8 * 8) + (to % 8)] = nil if piece.downcase == 'p' && to == @en_passant
      move_castling_rook(squares, from, to) if piece.downcase == 'k' && (to - from).abs == 2
      squares[to] = promotion ? promoted(promotion) : piece
      squares
    end

    def move_castling_rook(squares, from, to)
      rook_from = to > from ? from + 3 : from - 4
      squares[(from + to) / 2] = squares[rook_from]
      squares[rook_from] = nil
    end

    # Pawn moves and captures (en passant included, as it is a pawn move) reset the clock.
    def halfmove_after(from, to)
      @squares[from].downcase == 'p' || @squares[to] ? 0 : @halfmove + 1
    end

    def promoted(type)
      @side == 'w' ? type.upcase : type
    end

    def castling_after(from, to)
      lost = [CORNER_RIGHTS[from], CORNER_RIGHTS[to], KING_RIGHTS[@squares[from]]].join
      @castling.delete(lost)
    end

    def double_push?(from, to)
      @squares[from].downcase == 'p' && (to - from).abs == 16
    end

    def steps(from, offsets)
      offsets.filter_map { |file_step, rank_step| ChessRules.offset(from, file_step, rank_step) }
    end

    def reaches?(from, target, directions)
      directions.any? { |file_step, rank_step| ray_reaches?(from, target, file_step, rank_step) }
    end

    def ray_reaches?(from, target, file_step, rank_step)
      square = ChessRules.offset(from, file_step, rank_step)
      square = ChessRules.offset(square, file_step, rank_step) while square && square != target && @squares[square].nil?
      square == target
    end
  end
end
