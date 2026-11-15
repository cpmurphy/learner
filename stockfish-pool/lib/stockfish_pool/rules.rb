# frozen_string_literal: true

# position.rb, moves.rb and position_check.rb here are generated from the main
# app's ChessRules (lib/chess_rules) by bin/sync-chess-rules: edit those and
# run the script, rather than editing these.

require_relative 'rules/position'
require_relative 'rules/moves'
require_relative 'rules/position_check'

module StockfishPool
  module Rules
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

        current.after(Rules.square(move[0, 2]), Rules.square(move[2, 2]), move[4])
      end
      nil
    end
  end
end
