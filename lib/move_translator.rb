# frozen_string_literal: true

require_relative 'chess_rules'
require_relative 'uci_input_validator'

# Plays a game's moves, given in SAN as PGN files write them, and reports each
# one in UCI, the notation the engine takes. It keeps the position as it goes,
# so it can resolve moves that depend on it (which knight "Nbd7" means, en
# passant, castling). The rules, including the check that a move is legal,
# are ChessRules'.
#
#   translator = MoveTranslator.new
#   translator.translate_move("e4")     #=> "e2e4"
#   translator.translate_move("exd5")   #=> "e4d5"
#   translator.translate_move("a8=Q")   #=> "a7a8q"
#   translator.translate_move("O-O")    #=> "e1g1"
#   translator.translate_move("--")     #=> "--" (a null move)
#
# An illegal or unreadable move raises ChessRules::IllegalInput and leaves the
# position as it was.
class MoveTranslator
  START_FEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'

  def initialize
    @position = ChessRules::Position.from_fen(START_FEN)
  end

  def translate_moves(pgn_moves)
    pgn_moves.map { |move| translate_move(move) }
  end

  def translate_move(pgn_move)
    return play_null_move if pgn_move == '--'

    uci = ChessRules::San.parse(@position, pgn_move)
    @position = @position.after(*ChessRules::San.squares(uci))
    uci
  end

  def board_as_fen
    @position.to_fen
  end

  def load_game_from_fen(fen)
    raise ChessRules::IllegalInput, 'Invalid FEN' unless UciInputValidator.valid_fen?(fen)

    @position = ChessRules::Position.from_fen(fen)
  end

  private

  # The other side to move, with no en passant square; the board is unchanged.
  def play_null_move
    placement, side, castling, _en_passant, halfmove, fullmove = board_as_fen.split
    fullmove = fullmove.to_i + 1 if side == 'b'
    @position = ChessRules::Position.from_fen(
      [placement, side == 'w' ? 'b' : 'w', castling, '-', halfmove.to_i + 1, fullmove].join(' ')
    )
    '--'
  end
end
