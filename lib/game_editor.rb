# frozen_string_literal: true

module GameEditor
  # Modifies a PGN::Game object in place.
  # If a $201 annotation (critical moment) is found on move M,
  # it is moved to move M+1, as semantically $201 applies to the *next* move.
  # The PGN parser might associate it with M. This method corrects that.
  def self.shift_critical_annotations(game)
    return unless game&.moves && game.moves.size > 1

    # Iterate in reverse to avoid issues with modifying the array during iteration.
    (game.moves.size - 2).downto(0) do |i| # Iterate from second-to-last down to first move
      current_move_obj = game.moves[i]
      next_move_obj = game.moves[i + 1]

      next unless current_move_obj.annotation&.include?('$201')

      # Remove $201 from the current move
      current_move_obj.annotation.delete('$201')
      # Clean up annotation array if it becomes empty
      current_move_obj.annotation = nil if current_move_obj.annotation.empty?

      # Add $201 to the next move
      next_move_obj.annotation ||= [] # Initialize if nil
      next_move_obj.annotation << '$201' unless next_move_obj.annotation.include?('$201')
    end
  end
end
