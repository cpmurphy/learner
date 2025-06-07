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

  # Retrieves information about the move that LED to the current_position_index.
  # game: The PGN::Game object.
  # current_position_index: The index in game.positions array.
  #                         0 is the initial board state.
  #                         1 is the state after the first move (game.moves[0]), etc.
  # Returns a hash with move details, or nil if current_position_index is 0.
  def get_last_move_info(game, current_position_index)
    return nil if current_position_index == 0 || game.nil? || game.moves.empty?

    # The move that LED to the current_position_index
    # game.positions[0] is initial, game.moves[0] is the 1st move, leading to game.positions[1]
    actual_move_index_in_game_array = current_position_index - 1

    # Ensure actual_move_index_in_game_array is valid for game.moves
    return nil if actual_move_index_in_game_array < 0 || actual_move_index_in_game_array >= game.moves.size

    move = game.moves[actual_move_index_in_game_array]
    return nil unless move # Should exist if index is valid

    # Ensure actual_move_index_in_game_array is valid for game.positions (for fen_before_this_move)
    return nil if actual_move_index_in_game_array >= game.positions.size

    fen_before_this_move = game.positions[actual_move_index_in_game_array].to_fen.to_s

    is_critical_moment = move.annotation&.include?('$201')
    good_san = nil

    if is_critical_moment && move.variations && !move.variations.empty?
      first_variation = move.variations.first
      if first_variation && !first_variation.empty?
        good_san = first_variation.first.notation.to_s
      end
    end

    # Corrected move number calculation
    # actual_move_index_in_game_array 0 (White's 1st) -> (0/2)+1 = 1
    # actual_move_index_in_game_array 1 (Black's 1st) -> (1/2)+1 = 1
    # actual_move_index_in_game_array 2 (White's 2nd) -> (2/2)+1 = 2
    display_move_number = (actual_move_index_in_game_array / 2) + 1
    current_turn = (actual_move_index_in_game_array % 2 == 0) ? 'white' : 'black'

    {
      number: display_move_number, # Corrected display move number
      turn: current_turn,
      san: move.notation.to_s,
      comment: move.comment,
      annotation: move.annotation, # NAGs (Numeric Annotation Glyphs)
      is_critical: is_critical_moment,
      good_move_san: good_san,
      fen_before_move: fen_before_this_move
    }
  end
end
