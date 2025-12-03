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
      position_index = check_move_for_critical_moment(game_moves, move_array_idx, learning_side_to_check)
      return position_index if position_index
    end
    nil # No critical moment found
  end

  def check_move_for_critical_moment(game_moves, move_array_idx, learning_side_to_check)
    move = game_moves[move_array_idx]
    move_turn = determine_move_turn(move_array_idx)
    return nil unless move_turn == learning_side_to_check
    return nil unless move.annotation&.include?('$201')

    move_array_idx + 1 # Position index
  end

  def determine_move_turn(move_array_idx)
    # move_array_idx 0 is White's 1st move (leading to position 1)
    # move_array_idx 1 is Black's 1st move (leading to position 2)
    move_array_idx.even? ? 'white' : 'black'
  end

  # Retrieves information about the move that LED to the current_position_index.
  # game: The PGN::Game object.
  # current_position_index: The index in game.positions array.
  #                         0 is the initial board state.
  #                         1 is the state after the first move (game.moves[0]), etc.
  # Returns a hash with move details, or nil if current_position_index is 0.
  def get_last_move_info(game, current_position_index)
    return nil unless valid_move_info_params?(game, current_position_index)

    actual_move_index = current_position_index - 1
    return nil unless valid_move_index?(game, actual_move_index)

    move = game.moves[actual_move_index]
    return nil unless move

    build_move_info_hash(move, actual_move_index, game)
  end

  def valid_move_info_params?(game, current_position_index)
    !current_position_index.zero? && !game.nil? && !game.moves.empty?
  end

  def valid_move_index?(game, move_index)
    move_index >= 0 && move_index < game.moves.size && move_index < game.positions.size
  end

  def build_move_info_hash(move, actual_move_index, game)
    fen_before_this_move = game.positions[actual_move_index].to_fen.to_s
    is_critical_moment = move.annotation&.include?('$201')
    variation_data = extract_variation_data(move, is_critical_moment)
    move_metadata = calculate_move_metadata(actual_move_index)

    {
      number: move_metadata[:display_move_number],
      turn: move_metadata[:current_turn],
      san: move.notation.to_s,
      comment: move.comment,
      annotation: move.annotation, # NAGs (Numeric Annotation Glyphs)
      is_critical: is_critical_moment,
      good_move_san: variation_data[:good_san],
      variation_sans: variation_data[:variation_sans],
      fen_before_move: fen_before_this_move
    }
  end

  def extract_variation_data(move, is_critical_moment)
    return { good_san: nil, variation_sans: [] } unless is_critical_moment && move.variations && !move.variations.empty?

    first_variation_line = move.variations.first
    return { good_san: nil, variation_sans: [] } unless first_variation_line && !first_variation_line.empty?

    good_san = first_variation_line.first.notation.to_s
    variation_sans = first_variation_line.map { |var_move| var_move.notation.to_s }
    { good_san: good_san, variation_sans: variation_sans }
  end

  def calculate_move_metadata(actual_move_index)
    # actual_move_index 0 (White's 1st) -> (0/2)+1 = 1
    # actual_move_index 1 (Black's 1st) -> (1/2)+1 = 1
    # actual_move_index 2 (White's 2nd) -> (2/2)+1 = 2
    display_move_number = (actual_move_index / 2) + 1
    current_turn = actual_move_index.even? ? 'white' : 'black'
    { display_move_number: display_move_number, current_turn: current_turn }
  end
end
