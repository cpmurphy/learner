# frozen_string_literal: true

class AnnotationShifter
  # Modifies a PGN::Game object in place.
  # If a $201 annotation (critical moment) is found on move M,
  # it is moved to move M+1, as semantically $201 applies to the *next* move.
  # The PGN parser might associate it with M. This method corrects that.
  def shift_critical_annotations(game)
    moves = game.moves
    i = moves.size - 1
    while i.positive?
      current_move = moves[i]
      prev_move = moves[i - 1]

      # Only shift annotation to a real move, not MoveText.
      if should_shift_annotation?(prev_move, current_move)
        remove_201_from_move(prev_move)
        add_201_to_move(current_move)
      end
      i -= 1
    end
  end

  # Reverses shift_critical_annotations - moves $201 from move M+1 back to move M.
  # This is used when saving games that were analyzed by our system, where
  # add_blunder_annotations places $201 on move i-1 (before the blunder),
  # which is the correct placement for PGN files.
  def unshift_critical_annotations(game)
    moves = game.moves
    return if moves.empty?

    # Start from the beginning and move $201 backwards
    (1...moves.size).each do |i|
      current_move = moves[i]
      prev_move = moves[i - 1]

      next unless current_move.respond_to?(:annotation) && current_move.annotation&.include?('$201')

      # Only unshift annotation if previous move is a real move
      next unless prev_move.respond_to?(:annotation)

      remove_201_from_move(current_move)

      add_201_to_move(prev_move)
    end
  end

  # Adds a $201 annotation to the specified move
  # @param move [PGN::Move] the move to annotate
  def add_201_to_move(move)
    move.annotation ||= [] # Initialize if nil
    move.annotation << '$201' unless move.annotation.include?('$201')
  end

  private

  # Removes the $201 annotation from the specified move
  # @param move [PGN::Move] the move to remove annotation from
  def remove_201_from_move(move)
    move.annotation.delete('$201')
    move.annotation = nil if move.annotation.empty?
  end

  # Checks if annotation should be shifted from previous move to current move
  # @param prev_move [PGN::Move] the previous move
  # @param current_move [PGN::Move] the current move
  # @return [Boolean] true if the annotation should be shifted
  def should_shift_annotation?(prev_move, current_move)
    prev_move.respond_to?(:annotation) &&
      prev_move.annotation&.include?('$201') &&
      current_move.respond_to?(:annotation)
  end
end
