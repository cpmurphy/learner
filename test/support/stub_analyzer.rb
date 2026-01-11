# frozen_string_literal: true

# A stub Analyzer that returns simple, predictable results for testing
# without calling Stockfish. This avoids complex mocking in tests.
#
# This stub is designed to avoid triggering blunder detection by returning
# scores that are very close to each other (difference < 140 centipawns).
class StubAnalyzer
  # Returns a simple best move analysis
  def evaluate_best_move(_fen)
    # Return a result with a good score but no variation
    # The move value doesn't matter since we return the same score
    # for evaluate_move, avoiding blunder detection
    { score: 50, move: 'e2e4', variation: [] }
  end

  # Returns a simple move evaluation
  # Returns a score very close to evaluate_best_move to avoid triggering blunders
  # Difference is 50 - 49 = 1 centipawn, well below the 140 threshold
  def evaluate_move(_fen, _move)
    { score: -49 }
  end

  # No-op close method
  def close; end
end
