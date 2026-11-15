# frozen_string_literal: true

require_relative 'chess_rules'
require_relative 'uci_input_validator'

# Converts a UCI move (as the engine gives it) to SAN (as PGN files write it)
# for a given position, using ChessRules. Check and mate marks are left off.
#
#   UciToSanConverter.new.convert(start_fen, 'g1f3') #=> "Nf3"
class UciToSanConverter
  # @param fen [String] the position in FEN format
  # @param uci_move [String] the move in UCI format (e.g., "e2e4"), or "--" for a null move
  # @return [String, nil] the move in SAN format (e.g., "e4"), or nil if the
  #   FEN or move is malformed or the move is not legal in the position
  def convert(fen, uci_move)
    return uci_move if uci_move == '--'
    return nil unless UciInputValidator.valid_fen?(fen) && UciInputValidator.valid_uci_move?(uci_move)

    ChessRules::San.write(ChessRules::Position.from_fen(fen), uci_move, marks: false)
  rescue ChessRules::IllegalInput
    nil
  end
end
