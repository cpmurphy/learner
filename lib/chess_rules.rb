# frozen_string_literal: true

# App copy of stockfish-pool's StockfishPool::Rules. The pool repo is the
# source of truth; refresh with bin/sync-chess-rules (CI runs --check).
# san.rb is app-only.

require_relative 'chess_rules/position'
require_relative 'chess_rules/moves'
require_relative 'chess_rules/position_check'
require_relative 'chess_rules/san'

module ChessRules
  # The position or a move is not legal chess.
  class IllegalInput < StandardError; end

  module_function

  # Raises IllegalInput unless +fen+ is a legal position and every move in
  # +moves+ is legal where it is played.
  def check!(fen, moves)
    position = Position.from_fen(fen)
    reason = PositionCheck.problem(position)
    raise IllegalInput, "Illegal position: #{reason}" if reason

    moves.each_with_index.reduce(position) do |current, (move, index)|
      raise IllegalInput, "Illegal move #{move} (moves[#{index}])" unless Moves.legal?(current, move)

      current.after(ChessRules.square(move[0, 2]), ChessRules.square(move[2, 2]), move[4])
    end
    nil
  end
end
