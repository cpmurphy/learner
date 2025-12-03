# frozen_string_literal: true

# Integration tests for GameEditor that require Stockfish engine
# These tests are excluded from the default test run and can be run separately
# with: bundle exec rake test:integration

require_relative '../test_helper'
require_relative '../../lib/game_editor'
require_relative '../../lib/analyzer'
require_relative '../../lib/move_translator'
require_relative '../../lib/uci_to_san_converter'

class GameEditorIntegrationTest < Minitest::Test
  def test_b4_blunder_detection
    # Test the specific position where b4 is a blunder
    # Position: 3r4/p1k4p/1p1q2p1/2p2p2/2B5/P1Bp2P1/1P2rP1P/R2Q2K1 w - - 3 30
    # Best move: Qa4 (+2.5 pawns ~250 centipawns), Played move: b4 (-2.0 pawns ~-200 centipawns)
    # This should be detected as a blunder (difference > 4.5 pawns = 450 centipawns > 140 centipawns threshold)

    fen_position = '3r4/p1k4p/1p1q2p1/2p2p2/2B5/P1Bp2P1/1P2rP1P/R2Q2K1 w - - 3 30'

    analyzer = Analyzer.new
    begin
      # Get the best move analysis
      best_move_analysis = analyzer.evaluate_best_move(fen_position)

      # Convert b4 to UCI format
      translator = MoveTranslator.new
      translator.load_game_from_fen(fen_position)
      uci_b4 = translator.translate_move('b4')

      # Evaluate b4 move
      played_move_analysis = analyzer.evaluate_move(fen_position, uci_b4)

      # Calculate scores from White's perspective (the player making the move)
      best_score = best_move_analysis[:score]
      played_score = -played_move_analysis[:score] # Negate because evaluate_move returns from opponent's perspective

      # Verify the scores show b4 is significantly worse
      # Best move should have a positive score (advantage for White)
      assert_operator best_score, :>, 150, "Best move should have score > 150 centipawns (got #{best_score})"

      # b4 should have a significantly worse score (could be negative or much lower positive)
      # The key is that the difference is large

      # Calculate the difference
      score_diff = best_score - played_score

      # The score difference should be large enough to be a blunder
      # User stated: +2.5 to -2.0 = ~4.5 pawns = 450 centipawns
      # But we'll be more flexible and just verify it's above the threshold
      assert_operator score_diff, :>, GameEditor::BLUNDER_THRESHOLD, "Score difference (#{score_diff} cp) should exceed blunder threshold (#{GameEditor::BLUNDER_THRESHOLD} cp). Best: #{best_score} cp, Played: #{played_score} cp"

      # Verify the best move is Qa4
      best_move_uci = best_move_analysis[:move]
      translator2 = MoveTranslator.new
      translator2.load_game_from_fen(fen_position)
      uci_converter = UciToSanConverter.new
      best_move_san = uci_converter.convert(fen_position, best_move_uci)

      assert_equal 'Qa4', best_move_san, "Best move should be Qa4, not #{best_move_san}"
    ensure
      analyzer.close
    end
  end
end
