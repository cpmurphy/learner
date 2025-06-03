# frozen_string_literal: true

module AppHelpers
  # Helper to find the next critical moment for a given side
  # game_moves: The array of move objects (e.g., $game.moves)
  # start_search_from_move_index: The index in game_moves to start searching from.
  #                                This corresponds to the PGN move array index.
  #                                If $current_move_index (position index) is 0 (start of game), search from move 0.
  #                                If $current_move_index is N, the last move made was game_moves[N-1].
  #                                We search from game_moves[N] onwards.
  # learning_side_to_check: 'white' or 'black'
  # Returns the *position index* (move_array_idx + 1) of the critical move, or nil if not found.
  def find_critical_moment_position_index(game_moves, start_search_from_move_index, learning_side_to_check)
    return nil if game_moves.nil? || game_moves.empty?

    (start_search_from_move_index...game_moves.size).each do |move_array_idx|
      move = game_moves[move_array_idx]
      # Determine turn for game_moves[move_array_idx]
      # move_array_idx 0 is White's 1st move (leading to position 1)
      # move_array_idx 1 is Black's 1st move (leading to position 2)
      move_turn = (move_array_idx % 2 == 0) ? 'white' : 'black'

      if move_turn == learning_side_to_check && move.annotation&.include?('$201')
        return move_array_idx + 1 # Position index
      end
    end
    nil # No critical moment found
  end
end
