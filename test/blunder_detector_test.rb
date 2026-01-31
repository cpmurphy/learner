# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/blunder_detector'

class TestBlunderDetector < Minitest::Test
  def setup
    @detector = BlunderDetector.new
  end

  def test_blunder_detected_when_drop_exceeds_threshold
    # Best score: 200, played score: 50, difference: 150 > 140 (threshold)
    assert @detector.blunder_detected?(200, 50)
  end

  def test_blunder_not_detected_when_drop_below_threshold
    # Best score: 200, played score: 100, difference: 100 < 140 (threshold)
    refute @detector.blunder_detected?(200, 100)
  end

  def test_blunder_not_detected_when_played_score_500_plus_and_best_not_mate
    # Played score is 600 (500+), best score is 200 (not mate), should not be blunder
    # even though difference is negative (best_score < played_score)
    refute @detector.blunder_detected?(200, 600)
  end

  def test_blunder_detected_when_played_score_500_plus_and_best_is_mate_in_1
    # Played score is 600 (500+), best score is 999 (mate in 1)
    # Should be blunder because best move is mate in 1
    assert @detector.blunder_detected?(999, 600)
  end

  def test_blunder_detected_when_played_score_500_plus_and_best_is_mate_in_2
    # Played score is 600 (500+), best score is 998 (mate in 2)
    # Should be blunder because best move is mate in 2
    assert @detector.blunder_detected?(998, 600)
  end

  def test_blunder_detected_when_played_score_500_plus_and_best_is_mate_in_3
    # Played score is 600 (500+), best score is 997 (mate in 3)
    # Should be blunder because best move is mate in 3
    assert @detector.blunder_detected?(997, 600)
  end

  def test_blunder_not_detected_when_played_score_500_plus_and_best_is_mate_in_4
    # Played score is 600 (500+), best score is 996 (mate in 4)
    # Should NOT be blunder because mate in 4 is not forced enough
    refute @detector.blunder_detected?(996, 600)
  end

  def test_blunder_not_detected_when_played_score_above_250_and_best_less_than_30_percent_better
    # Played score is 300, best score is 350
    # Difference: 50 < 140, but also best is only 16% better, not 30%+
    refute @detector.blunder_detected?(350, 300)
  end

  def test_blunder_detected_when_played_score_above_250_and_best_more_than_30_percent_better
    # Played score is 300, best score is 500
    # Difference: 200 > 140, and best is 66% better (> 30%)
    # Should be blunder
    assert @detector.blunder_detected?(500, 300)
  end

  def test_blunder_not_detected_when_played_score_above_250_and_best_less_than_30_percent_better_large_difference
    # Played score is 300, best score is 380
    # Difference: 80 < 140, but testing edge case where difference is large but not 30% better
    refute @detector.blunder_detected?(380, 300)
  end

  def test_blunder_detected_when_played_score_250_or_less_and_difference_exceeds_threshold
    # Played score is 250 (exactly at boundary), best score is 400
    # Difference: 150 > 140, should be blunder
    assert @detector.blunder_detected?(400, 250)
  end

  def test_blunder_detected_when_played_score_below_250_and_difference_exceeds_threshold
    # Played score is 100, best score is 250
    # Difference: 150 > 140, should be blunder
    assert @detector.blunder_detected?(250, 100)
  end

  def test_blunder_not_detected_when_scores_equal
    # No advantage gained or lost
    refute @detector.blunder_detected?(200, 200)
  end

  def test_blunder_not_detected_when_played_better_than_best
    # This shouldn't happen in practice, but played move is better than "best"
    refute @detector.blunder_detected?(100, 200)
  end

  def test_blunder_threshold_constant
    assert_equal 140, BlunderDetector::BLUNDER_THRESHOLD
  end

  def test_blunder_not_detected_when_both_moves_completely_lost
    # Both moves leave the position completely lost (losing by 8+ pawns)
    # Best score: -401, played score: -893, difference: -492 (but both are completely lost)
    # Should NOT be blunder because game is hopeless either way
    refute @detector.blunder_detected?(-401, -893)
  end

  def test_blunder_not_detected_when_both_moves_exactly_at_lost_threshold
    # Both scores are exactly at the completely lost threshold (-400)
    # Should NOT be blunder
    refute @detector.blunder_detected?(-400, -400)
  end

  def test_blunder_detected_when_only_played_move_completely_lost
    assert @detector.blunder_detected?(-300, -441)
  end

  def test_blunder_detected_when_neither_move_completely_lost
    # Neither move is completely lost, normal blunder detection should apply
    # Best score: -200, played score: -350, difference: 150 > 140
    # Should be blunder
    assert @detector.blunder_detected?(-200, -350)
  end

  def test_completely_lost_threshold_constant
    assert_equal(-400, BlunderDetector::COMPLETELY_LOST_THRESHOLD)
  end
end
