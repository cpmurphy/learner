# frozen_string_literal: true

require_relative 'move_translator'

# Checks that a game pasted by an anonymous visitor is a legal game from the
# standard starting position, before any of its positions reach the engine.
#
# The pgn gem builds positions without checking legality, and
# UciInputValidator only checks a FEN's shape, so a crafted game could hand
# Stockfish an impossible position (say, the side not to move in check), which
# it does not support. This replays the game on MoveTranslator's board and
# requires, after every move, that:
# - the move was one the piece can make (MoveTranslator raises otherwise);
# - the side that moved is not left in check;
# - no pawn stands on the first or eighth rank;
# - the pgn gem's position (what the engine will see) matches the replay.
module GameLegality
  STANDARD_START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'

  module_function

  # Returns nil for a legal game, or a message for the visitor.
  def problem(game)
    return 'The game must start from the standard starting position.' unless standard_start?(game)

    board = Translator::Board.new
    translator = MoveTranslator.new(board)
    game.moves.each_with_index do |move, index|
      problem = move_problem(translator, board, move.notation, game.positions[index + 1])
      return "Move #{move_label(index, move.notation)} is not legal: #{problem}." if problem
    end
    nil
  end

  def standard_start?(game)
    game.positions.first&.to_fen.to_s == STANDARD_START
  end

  # The squares a castling king starts on and crosses; neither may be attacked.
  CASTLING_SQUARES = {
    [:white, false] => %w[e1 f1], [:white, true] => %w[e1 d1],
    [:black, false] => %w[e8 f8], [:black, true] => %w[e8 d8]
  }.freeze

  def move_problem(translator, board, notation, position)
    problem = before_move_problem(board, notation) || play(translator, notation)
    return problem if problem
    return 'it leaves the king in check' if mover_in_check?(board)

    position_problem(translator.board_as_fen.split.first, position)
  end

  def before_move_problem(board, notation)
    return 'null moves are not supported' if notation == '--'

    'the king cannot castle out of or through check' if castles_through_check?(board, notation)
  end

  def play(translator, notation)
    translator.translate_move(notation)
    nil
  rescue StandardError
    'that piece cannot move there'
  end

  def position_problem(placement, position)
    return 'a pawn cannot stand on the first or last rank' if pawn_on_back_rank?(placement)
    return 'it could not be replayed' unless position && position.to_fen.to_s.split.first == placement

    nil
  end

  # After a move the board's current player is the opponent; the move was
  # illegal if the opponent now attacks the mover's king (or it has none).
  def mover_in_check?(board)
    board.switch_player
    king = board.find_king
    king.nil? || board.opponent_attacks_square?(king)
  ensure
    board.switch_player
  end

  # Called before the move, so the board's current player is the one castling.
  def castles_through_check?(board, notation)
    return false unless notation.match?(/\AO-O(-O)?[+#]?\z/)

    squares = CASTLING_SQUARES.fetch([board.current_player, notation.start_with?('O-O-O')])
    squares.any? { |square| board.opponent_attacks_square?(square) }
  end

  def pawn_on_back_rank?(placement)
    ranks = placement.split('/')
    [ranks.first, ranks.last].any? { |rank| rank.to_s.match?(/[pP]/) }
  end

  def move_label(index, notation)
    number = (index / 2) + 1
    index.even? ? "#{number}. #{notation}" : "#{number}... #{notation}"
  end
end
