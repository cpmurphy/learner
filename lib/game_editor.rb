# frozen_string_literal: true

module GameEditor
  # Modifies a PGN::Game object in place.
  # If a $201 annotation (critical moment) is found on move M,
  # it is moved to move M+1, as semantically $201 applies to the *next* move.
  # The PGN parser might associate it with M. This method corrects that.
  def self.shift_critical_annotations(game)
    moves = game.moves
    i = moves.size - 1
    while i.positive?
      current_move = moves[i]
      prev_move = moves[i - 1]

      if prev_move.annotation&.include?('$201')
        remove_201_from_move(prev_move)

        add_201_to_move(current_move)
      end
      i -= 1
    end
  end

  def self.remove_201_from_move(move)
    move.annotation.delete('$201')
    move.annotation = nil if move.annotation.empty?
  end

  def self.add_201_to_move(move)
    move.annotation ||= [] # Initialize if nil
    move.annotation << '$201' unless move.annotation.include?('$201')
  end
end
