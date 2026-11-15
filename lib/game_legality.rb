# frozen_string_literal: true

require_relative 'chess_rules'
require_relative 'move_translator'
require_relative 'uci_input_validator'

# Checks that a game pasted by an anonymous visitor is a legal game from the
# standard starting position, before any of its positions reach the engine.
#
# The pgn gem builds positions without checking legality, so a crafted game
# could hand Stockfish an impossible position, which it does not support.
# MoveTranslator turns each SAN move into UCI (it has the board to work out
# which piece moves); ChessRules then decides whether that move is legal.
# After every move the pgn gem's position, which is what the engine will see,
# must be a legal position with the board ChessRules expects.
module GameLegality
  STANDARD_START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'

  module_function

  # Returns nil for a legal game, or a message for the visitor.
  def problem(game)
    return 'The game must start from the standard starting position.' unless standard_start?(game)

    translator = MoveTranslator.new
    position = ChessRules::Position.from_fen(STANDARD_START)
    game.moves.each_with_index do |move, index|
      position, problem = play(translator, position, move.notation)
      problem ||= position_problem(position, game.positions[index + 1])
      return "Move #{move_label(index, move.notation)} is not legal: #{problem}." if problem
    end
    nil
  end

  def standard_start?(game)
    game.positions.first&.to_fen.to_s == STANDARD_START
  end

  # Returns [position after the move, nil] or [nil, the problem].
  def play(translator, position, notation)
    return [nil, 'null moves are not supported'] if notation == '--'

    uci = translator_uci(translator, notation)
    return [nil, 'that piece cannot move there'] unless uci

    from, to, promotion = squares(uci)
    return [nil, illegal_reason(position, from, to, promotion)] unless ChessRules::Moves.legal?(position, uci)

    [position.after(from, to, promotion), nil]
  end

  # The move in UCI, or nil when no piece can make it.
  def translator_uci(translator, notation)
    uci = translator.translate_move(notation)
    uci if UciInputValidator.valid_uci_move?(uci)
  rescue StandardError
    nil
  end

  def squares(uci)
    [ChessRules.square(uci[0, 2]), ChessRules.square(uci[2, 2]), uci[4]]
  end

  # Why ChessRules refused a move the translator could play.
  def illegal_reason(position, from, to, promotion)
    castle = ChessRules::Moves::CASTLES[[from, to]]
    return castling_reason(position, castle) if castle && position[from]&.downcase == 'k'
    return 'it leaves the king in check' if ChessRules::Moves.reachable?(position, from, to, promotion)
    return 'a pawn reaching the last rank must promote' if unpromoted_pawn?(position, from, to, promotion)

    'that piece cannot move there'
  end

  def castling_reason(position, castle)
    right, rook, empty, = castle
    if ChessRules::Moves.castling_right?(position, right, rook) && empty.none? { |square| position[square] }
      'the king cannot castle out of, through or into check'
    else
      'castling is no longer allowed'
    end
  end

  def unpromoted_pawn?(position, from, to, promotion)
    position[from]&.downcase == 'p' && promotion.nil? && [0, 7].include?(to / 8)
  end

  # The pgn gem's position after the move must be one the engine can be given,
  # with the board the move produced.
  def position_problem(expected, actual)
    return 'it could not be replayed' unless actual

    fen = actual.to_fen.to_s
    return 'it could not be replayed' unless UciInputValidator.valid_fen?(fen)

    ChessRules.check!(fen, [])
    'it could not be replayed' unless fen.split.first == expected.placement
  rescue ChessRules::IllegalInput => e
    "it leads to an illegal position (#{e.message.delete_prefix('Illegal position: ')})"
  end

  def move_label(index, notation)
    number = (index / 2) + 1
    index.even? ? "#{number}. #{notation}" : "#{number}... #{notation}"
  end
end
