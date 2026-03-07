# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/mock'
require 'pgn' # Gem for PGN parsing, used to construct test objects
require_relative '../lib/app_helpers' # For testing AppHelpers module

# --- Tests for AppHelpers ---
class TestAppFindCriticalMomentHelper < Minitest::Test
  include AppHelpers # Make helper method available

  # Helper to create a mock PGN::Move object
  def mock_move(annotation_array = nil)
    move = PGN::MoveText.new('') # Notation doesn't matter for this helper
    move.annotation = annotation_array if annotation_array
    move
  end

  def test_find_critical_no_moves
    assert_nil find_critical_moment_position_index([], 0, 'white')
  end

  def test_find_critical_nil_moves
    assert_nil find_critical_moment_position_index(nil, 0, 'white')
  end

  def test_find_critical_no_critical_moments
    moves = [mock_move, mock_move(['$1']), mock_move]

    assert_nil find_critical_moment_position_index(moves, 0, 'white')
    assert_nil find_critical_moment_position_index(moves, 0, 'black')
  end

  def test_find_critical_moment_for_white_at_start
    moves = [mock_move(['$201']), mock_move] # White's 1st move (idx 0) is critical

    assert_equal 1, find_critical_moment_position_index(moves, 0, 'white') # Position index 1
  end

  def test_find_critical_moment_for_black_at_start
    moves = [mock_move, mock_move(['$201'])] # Black's 1st move (idx 1) is critical

    assert_equal 2, find_critical_moment_position_index(moves, 0, 'black') # Position index 2
  end

  def test_find_critical_moment_for_white_later
    moves = [mock_move, mock_move, mock_move(['$201']), mock_move] # White's 2nd move (idx 2) is critical

    assert_equal 3, find_critical_moment_position_index(moves, 0, 'white') # Position index 3
  end

  def test_find_critical_moment_for_black_later
    moves = [mock_move, mock_move, mock_move, mock_move(['$201'])] # Black's 2nd move (idx 3) is critical

    assert_equal 4, find_critical_moment_position_index(moves, 0, 'black') # Position index 4
  end

  def test_find_critical_search_starts_after_a_critical_moment
    moves = [
      mock_move(['$201']), # White's 1st (pos 1)
      mock_move,
      mock_move(['$201']), # White's 2nd (pos 3)
      mock_move
    ]
    # Start search from move index 1 (after White's 1st critical move)
    assert_equal 3, find_critical_moment_position_index(moves, 1, 'white')
  end

  def test_find_critical_search_starts_at_a_critical_moment
    moves = [
      mock_move,
      mock_move(['$201']), # Black's 1st (pos 2)
      mock_move,
      mock_move(['$201'])  # Black's 2nd (pos 4)
    ]
    # Start search from move index 1 (Black's 1st critical move)
    assert_equal 2, find_critical_moment_position_index(moves, 1, 'black')
  end

  def test_find_critical_search_starts_after_all_critical_moments_for_side
    moves = [mock_move(['$201']), mock_move, mock_move(['$1'])]
    # Start search from move index 1 (after White's only critical move)
    assert_nil find_critical_moment_position_index(moves, 1, 'white')
  end

  def test_find_critical_moment_only_for_specified_side
    moves = [mock_move(['$201']), mock_move(['$201'])] # White critical, then Black critical

    assert_equal 1, find_critical_moment_position_index(moves, 0, 'white')
    assert_equal 2, find_critical_moment_position_index(moves, 0, 'black')
    # Start search for white from move 1 (after white's critical, at black's critical)
    assert_nil find_critical_moment_position_index(moves, 1, 'white')
  end

  def test_find_critical_moment_with_other_annotations
    moves = [mock_move(['$1', '$201', '$2'])]

    assert_equal 1, find_critical_moment_position_index(moves, 0, 'white')
  end
end
