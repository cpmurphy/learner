# frozen_string_literal: true

require 'pgn'

# UciToSanConverter converts moves from UCI format to Standard Algebraic Notation (SAN)
#
# UCI format examples: "e2e4", "g1f3", "e7e8q", "e1g1" (castling)
# SAN format examples: "e4", "Nf3", "e8=Q", "O-O"
#
# Usage:
#   converter = UciToSanConverter.new
#   san = converter.convert(fen, uci_move)
#
class UciToSanConverter
  PIECE_SYMBOLS = {
    'P' => '', 'p' => '',     # Pawns have no symbol in SAN
    'N' => 'N', 'n' => 'N',   # Knight
    'B' => 'B', 'b' => 'B',   # Bishop
    'R' => 'R', 'r' => 'R',   # Rook
    'Q' => 'Q', 'q' => 'Q',   # Queen
    'K' => 'K', 'k' => 'K'    # King
  }.freeze

  # Convert a UCI move to SAN format
  #
  # @param fen [String] the position in FEN format
  # @param uci_move [String] the move in UCI format (e.g., "e2e4")
  # @return [String] the move in SAN format (e.g., "e4")
  def convert(fen, uci_move)
    return uci_move if uci_move == '--' # Null move

    context = parse_move_context(fen, uci_move)
    return uci_move unless context[:piece] # Invalid move

    castling_move = detect_castling(context)
    return castling_move if castling_move

    san = build_san(context)
    validate_and_fix_san(context, san)
  end

  private

  # Parse UCI move and FEN into a context hash
  #
  # @param fen [String] the position in FEN format
  # @param uci_move [String] the move in UCI format
  # @return [Hash] context hash with position, piece, squares, etc.
  def parse_move_context(fen, uci_move)
    fen_obj = PGN::FEN.new(fen)
    position = fen_obj.to_position
    from_square = uci_move[0..1]
    to_square = uci_move[2..3]
    promotion = uci_move[4]&.upcase
    piece = position.board.at(from_square)
    en_passant_square = fen_obj.en_passant == '-' ? nil : fen_obj.en_passant

    {
      position: position,
      piece: piece,
      from_square: from_square,
      to_square: to_square,
      promotion: promotion,
      en_passant_square: en_passant_square
    }
  end

  # Detect if move is castling and return SAN notation
  #
  # @param context [Hash] move context
  # @return [String, nil] castling notation or nil
  def detect_castling(context)
    piece = context[:piece]
    from_square = context[:from_square]
    to_square = context[:to_square]

    return nil unless piece.upcase == 'K'
    return nil unless (from_square[0].ord - to_square[0].ord).abs > 1

    to_square[0] > from_square[0] ? 'O-O' : 'O-O-O'
  end

  # Build SAN notation from move context
  #
  # @param context [Hash] move context
  # @return [String] SAN notation
  def build_san(context)
    position = context[:position]
    piece = context[:piece]
    from_square = context[:from_square]
    to_square = context[:to_square]
    promotion = context[:promotion]
    en_passant_square = context[:en_passant_square]

    piece_symbol = PIECE_SYMBOLS[piece]
    is_capture = position.board.at(to_square) || en_passant?(piece, from_square, to_square, en_passant_square)

    if piece.upcase == 'P'
      build_pawn_san(from_square, to_square, promotion, is_capture)
    else
      build_piece_san(context, piece_symbol, is_capture)
    end
  end

  # Build SAN notation for a pawn move
  #
  # @param from_square [String] source square
  # @param to_square [String] destination square
  # @param promotion [String, nil] promotion piece
  # @param is_capture [Boolean] whether this is a capture
  # @return [String] SAN notation
  def build_pawn_san(from_square, to_square, promotion, is_capture)
    san = ''
    san += "#{from_square[0]}x" if is_capture
    san += to_square
    san += "=#{promotion}" if promotion
    san
  end

  # Build SAN notation for a piece move
  #
  # @param context [Hash] move context
  # @param piece_symbol [String] SAN piece symbol
  # @param is_capture [Boolean] whether this is a capture
  # @return [String] SAN notation
  def build_piece_san(context, piece_symbol, is_capture)
    position = context[:position]
    piece = context[:piece]
    from_square = context[:from_square]
    to_square = context[:to_square]

    san = piece_symbol
    disambiguation = find_disambiguation(position, piece, from_square, to_square)
    san += disambiguation if disambiguation
    san += 'x' if is_capture
    san + to_square
  end

  # Validate SAN and fix if needed
  #
  # @param context [Hash] move context
  # @param san [String] initial SAN attempt
  # @return [String] validated SAN
  def validate_and_fix_san(context, san)
    context[:position].move(san)
    san
  rescue StandardError
    build_san(context) # Rebuild with disambiguation
  end

  def en_passant?(piece, from_square, to_square, en_passant_square)
    return false unless piece.upcase == 'P'
    return false unless en_passant_square

    # En passant: pawn moves diagonally to the en passant square
    to_square == en_passant_square && from_square[0] != to_square[0]
  end

  def find_disambiguation(position, piece, from_square, to_square)
    same_piece_squares = find_ambiguous_pieces(position, piece, from_square, to_square)
    return nil if same_piece_squares.empty?

    determine_disambiguation_string(from_square, same_piece_squares)
  end

  # Find all pieces of the same type that could move to the destination
  #
  # @param position [PGN::Position] chess position
  # @param piece [String] piece character
  # @param from_square [String] source square
  # @param to_square [String] destination square
  # @return [Array<String>] array of squares with ambiguous pieces
  def find_ambiguous_pieces(position, piece, from_square, to_square)
    same_piece_squares = []

    ('a'..'h').each do |file|
      ('1'..'8').each do |rank|
        square = "#{file}#{rank}"
        square_piece = position.board.at(square)
        next unless square_piece == piece
        next if square == from_square

        same_piece_squares << square if can_piece_move?(position, square, to_square, piece)
      end
    end

    same_piece_squares
  end

  # Determine the disambiguation string needed
  #
  # @param from_square [String] source square
  # @param same_piece_squares [Array<String>] squares with ambiguous pieces
  # @return [String] disambiguation string
  def determine_disambiguation_string(from_square, same_piece_squares)
    same_file = same_piece_squares.any? { |sq| sq[0] == from_square[0] }
    same_rank = same_piece_squares.any? { |sq| sq[1] == from_square[1] }

    if !same_file
      from_square[0] # File disambiguation
    elsif !same_rank
      from_square[1] # Rank disambiguation
    else
      from_square # Full square disambiguation
    end
  end

  # Check if a piece can move from one square to another based on piece movement rules
  def can_piece_move?(position, from_square, to_square, piece)
    piece_type = piece.upcase

    case piece_type
    when 'N'
      can_knight_move?(from_square, to_square)
    when 'B'
      can_bishop_move?(position, from_square, to_square)
    when 'R'
      can_rook_move?(position, from_square, to_square)
    when 'Q'
      can_queen_move?(position, from_square, to_square)
    when 'K'
      can_king_move?(from_square, to_square)
    else
      false
    end
  end

  def can_knight_move?(from_square, to_square)
    file_diff = (from_square[0].ord - to_square[0].ord).abs
    rank_diff = (from_square[1].to_i - to_square[1].to_i).abs
    (file_diff == 2 && rank_diff == 1) || (file_diff == 1 && rank_diff == 2)
  end

  def can_bishop_move?(position, from_square, to_square)
    file_diff = (from_square[0].ord - to_square[0].ord).abs
    rank_diff = (from_square[1].to_i - to_square[1].to_i).abs
    return false unless file_diff == rank_diff && file_diff.positive?

    path_clear?(position, from_square, to_square)
  end

  def can_rook_move?(position, from_square, to_square)
    same_file = from_square[0] == to_square[0]
    same_rank = from_square[1] == to_square[1]
    return false unless same_file || same_rank

    path_clear?(position, from_square, to_square)
  end

  def can_queen_move?(position, from_square, to_square)
    can_rook_move?(position, from_square, to_square) ||
      can_bishop_move?(position, from_square, to_square)
  end

  def can_king_move?(from_square, to_square)
    file_diff = (from_square[0].ord - to_square[0].ord).abs
    rank_diff = (from_square[1].to_i - to_square[1].to_i).abs
    file_diff <= 1 && rank_diff <= 1 && (file_diff.positive? || rank_diff.positive?)
  end

  def path_clear?(position, from_square, to_square)
    from_file = from_square[0].ord
    from_rank = from_square[1].to_i
    to_file = to_square[0].ord
    to_rank = to_square[1].to_i

    file_step = to_file <=> from_file
    rank_step = to_rank <=> from_rank

    current_file = from_file + file_step
    current_rank = from_rank + rank_step

    while current_file != to_file || current_rank != to_rank
      square = "#{current_file.chr}#{current_rank}"
      return false if position.board.at(square)

      current_file += file_step if file_step != 0
      current_rank += rank_step if rank_step != 0
    end

    true
  end
end
