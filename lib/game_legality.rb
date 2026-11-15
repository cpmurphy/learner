# frozen_string_literal: true

require_relative 'chess_rules'
require_relative 'uci_input_validator'

# Checks that a game pasted by an anonymous visitor is a legal game from the
# standard starting position, before any of its positions reach the engine.
#
# The pgn gem builds positions without checking legality, so a crafted game
# could hand Stockfish an impossible position, which it does not support.
# ChessRules replays the game, refusing any move that is not legal, and after
# every move the pgn gem's position, which is what the engine will see, must
# be a legal position matching the replay.
module GameLegality
  STANDARD_START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'

  module_function

  # Returns nil for a legal game, or a message for the visitor.
  def problem(game)
    return 'The game must start from the standard starting position.' unless standard_start?(game)

    position = ChessRules::Position.from_fen(STANDARD_START)
    game.moves.each_with_index do |move, index|
      position, problem = play(position, move.notation)
      problem ||= position_problem(position, game.positions[index + 1])
      return "Move #{move_label(index, move.notation)} is not legal: #{problem}." if problem
    end
    nil
  end

  def standard_start?(game)
    game.positions.first&.to_fen.to_s == STANDARD_START
  end

  # Returns [position after the move, nil] or [nil, the problem].
  def play(position, notation)
    return [nil, 'null moves are not supported'] if notation == '--'

    uci = ChessRules::San.parse(position, notation)
    [position.after(*ChessRules::San.squares(uci)), nil]
  rescue ChessRules::IllegalInput => e
    [nil, e.message]
  end

  # The pgn gem's position after the move must be one the engine can be given,
  # and match the replay in everything but the move clocks.
  def position_problem(expected, actual)
    return 'it could not be replayed' unless actual

    fen = actual.to_fen.to_s
    return 'it could not be replayed' unless UciInputValidator.valid_fen?(fen)

    ChessRules.check!(fen, [])
    'it could not be replayed' unless fen.split.first(4) == expected.to_fen.split.first(4)
  rescue ChessRules::IllegalInput => e
    "it leads to an illegal position (#{e.message.delete_prefix('Illegal position: ')})"
  end

  def move_label(index, notation)
    number = (index / 2) + 1
    index.even? ? "#{number}. #{notation}" : "#{number}... #{notation}"
  end
end
