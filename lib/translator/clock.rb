# frozen_string_literal: true

module Translator
  # Manages chess game clocks (halfmove and fullmove)
  class Clock
    def initialize
      @halfmove_clock = 0
      @fullmove_number = 1
    end

    attr_accessor :halfmove_clock, :fullmove_number

    def update_clocks(current_player, piece_moved, capture)
      if (piece_moved && piece_moved.upcase == 'P') || capture
        @halfmove_clock = 0
      else
        @halfmove_clock += 1
      end

      @fullmove_number += 1 if current_player == :black
    end
  end
end
