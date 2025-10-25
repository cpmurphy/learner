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

    position = PGN::FEN.new(fen).to_position
    from_square = uci_move[0..1]
    to_square = uci_move[2..3]
    promotion = uci_move[4]&.upcase

    piece = position.board.at(from_square)
    return uci_move unless piece # Invalid move

    # Handle castling
    if piece.upcase == 'K' && (from_square[0].ord - to_square[0].ord).abs > 1
      return to_square[0] > from_square[0] ? 'O-O' : 'O-O-O'
    end

    # Build SAN notation
    san = build_san(position, piece, from_square, to_square, promotion)

    # Check if move results in check or checkmate
    begin
      new_position = position.move(san)
      # Try to detect check by seeing if the opponent's king is attacked
      # For simplicity, we'll skip check detection for now
      # The move is valid if we got here
    rescue StandardError
      # If the simple SAN doesn't work, we might need disambiguation
      san = build_san_with_disambiguation(position, piece, from_square, to_square, promotion)
    end

    san
  end

  private

  def build_san(position, piece, from_square, to_square, promotion)
    piece_symbol = PIECE_SYMBOLS[piece]
    is_capture = position.board.at(to_square) || is_en_passant?(position, piece, from_square, to_square)

    san = ''

    if piece.upcase == 'P'
      # Pawn moves
      if is_capture
        san += from_square[0] # File of origin for pawn captures
        san += 'x'
      end
      san += to_square
      san += "=#{promotion}" if promotion
    else
      # Piece moves
      san += piece_symbol
      san += 'x' if is_capture
      san += to_square
    end

    san
  end

  def build_san_with_disambiguation(position, piece, from_square, to_square, promotion)
    piece_symbol = PIECE_SYMBOLS[piece]
    is_capture = position.board.at(to_square) || is_en_passant?(position, piece, from_square, to_square)

    san = ''

    if piece.upcase == 'P'
      # Pawn moves
      if is_capture
        san += from_square[0]
        san += 'x'
      end
      san += to_square
      san += "=#{promotion}" if promotion
    else
      # Piece moves with disambiguation
      san += piece_symbol

      # Find other pieces of the same type that can move to the same square
      disambiguation = find_disambiguation(position, piece, from_square, to_square)
      san += disambiguation if disambiguation

      san += 'x' if is_capture
      san += to_square
    end

    san
  end

  def is_en_passant?(position, piece, from_square, to_square)
    return false unless piece.upcase == 'P'
    return false unless position.en_passant

    # En passant: pawn moves diagonally to the en passant square
    to_square == position.en_passant && from_square[0] != to_square[0]
  end

  def find_disambiguation(position, piece, from_square, to_square)
    # Find all pieces of the same type and color that could move to to_square
    same_piece_squares = []

    # Iterate through all squares on the board
    ('a'..'h').each do |file|
      ('1'..'8').each do |rank|
        square = "#{file}#{rank}"
        square_piece = position.board.at(square)
        next unless square_piece == piece
        next if square == from_square

        same_piece_squares << square
      end
    end

    return nil if same_piece_squares.empty?

    # Check if any other piece can legally move to the destination
    # For simplicity, we'll use file disambiguation if pieces are on different files
    # or rank disambiguation if they're on the same file

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
end
