# frozen_string_literal: true

class BlunderDetector
  BLUNDER_THRESHOLD = 140 # In centipawns. A drop of 1.4 pawn value is a blunder.

  # Determines if a move is a blunder based on the evaluation drop
  # @param best_score [Integer] evaluation of the best move in centipawns
  # @param played_score [Integer] evaluation of the played move in centipawns
  # @return [Boolean] true if the move is a blunder
  def blunder_detected?(best_score, played_score)
    # Now both scores are from the perspective of the player who is about to move.
    # A blunder means the evaluation drops significantly (for both White and Black).

    # A move should not be considered a blunder if it is 500 centipawns (or more) in favor
    # of the player making the move, unless the winning move is a forced mate in one, two or three moves.
    if played_score >= 500
      # Check if best move is mate in 1, 2, or 3 (scores 999, 998, or 997)
      is_forced_mate_in_1_2_or_3 = best_score.between?(997, 999)
      return false unless is_forced_mate_in_1_2_or_3
    end

    # A move should not be considered a blunder if it is more than 250 centipawns in favor
    # of the player making it, unless the best move has an evaluation more than 30% better.
    if played_score > 250
      # Check if best move is more than 30% better (best_score > played_score * 1.3)
      is_more_than_30_percent_better = best_score > (played_score * 1.3)
      return false unless is_more_than_30_percent_better
    end

    (best_score - played_score) > BLUNDER_THRESHOLD
  end
end
