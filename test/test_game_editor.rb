# frozen_string_literal: true

require 'minitest/autorun'
require 'pgn' # Gem for PGN parsing, used to construct test objects
require_relative '../lib/game_editor'
require_relative '../lib/app_helpers' # For testing AppHelpers module

# Mock PGN::Move and PGN::Game classes for testing without full PGN parsing
# This allows us to focus on the annotation shifting logic.
module PGN
  class Move
    attr_accessor :notation, :annotation, :variations, :comment, :number, :turn

    def initialize(notation, annotation = nil)
      @notation = notation
      @annotation = annotation ? annotation.dup : nil # Ensure we have a mutable copy
      @variations = []
      @comment = nil
    end
  end

  class Game
    attr_accessor :moves, :tags

    def initialize
      @moves = []
      @tags = {}
    end
  end
end

class TestGameEditor < Minitest::Test
  def setup
    @editor = GameEditor
  end

  def test_no_moves
    game = PGN::Game.new
    @editor.shift_critical_annotations(game)
    assert_empty game.moves
  end

  def test_one_move_with_annotation
    game = PGN::Game.new
    game.moves << PGN::Move.new('e4', ['$201'])
    @editor.shift_critical_annotations(game)
    assert_equal ['$201'], game.moves[0].annotation, "Annotation should remain on the only move"
  end

  def test_shifts_201_to_next_move
    game = PGN::Game.new
    game.moves << PGN::Move.new('e4', ['$201'])
    game.moves << PGN::Move.new('e5')
    @editor.shift_critical_annotations(game)
    assert_nil game.moves[0].annotation, "Annotation should be removed from the first move"
    assert_equal ['$201'], game.moves[1].annotation, "Annotation should be added to the second move"
  end

  def test_shifts_201_when_next_move_has_annotations
    game = PGN::Game.new
    game.moves << PGN::Move.new('e4', ['$201'])
    game.moves << PGN::Move.new('e5', ['$1']) # Next move already has an annotation
    @editor.shift_critical_annotations(game)
    assert_nil game.moves[0].annotation
    assert_includes game.moves[1].annotation, '$201'
    assert_includes game.moves[1].annotation, '$1'
    assert_equal 2, game.moves[1].annotation.size
  end

  def test_does_not_shift_other_annotations
    game = PGN::Game.new
    game.moves << PGN::Move.new('Nf3', ['$1', '$201'])
    game.moves << PGN::Move.new('Nf6')
    @editor.shift_critical_annotations(game)
    assert_equal ['$1'], game.moves[0].annotation, "Only $201 should be removed"
    assert_equal ['$201'], game.moves[1].annotation
  end

  def test_annotation_becomes_nil_if_201_was_only_one
    game = PGN::Game.new
    game.moves << PGN::Move.new('d4', ['$201'])
    game.moves << PGN::Move.new('d5')
    @editor.shift_critical_annotations(game)
    assert_nil game.moves[0].annotation, "Annotation array should become nil if $201 was the only one"
    assert_equal ['$201'], game.moves[1].annotation
  end

  def test_multiple_shifts_in_a_game
    game = PGN::Game.new
    game.moves << PGN::Move.new('e4', ['$201']) # Shift to m2
    game.moves << PGN::Move.new('e5')
    game.moves << PGN::Move.new('Nf3', ['$201']) # Shift to m4
    game.moves << PGN::Move.new('Nc6')
    game.moves << PGN::Move.new('Bc4') # No annotation initially

    @editor.shift_critical_annotations(game)

    assert_nil game.moves[0].annotation
    assert_equal ['$201'], game.moves[1].annotation

    assert_nil game.moves[2].annotation
    assert_equal ['$201'], game.moves[3].annotation

    assert_nil game.moves[4].annotation
  end

  def test_201_on_last_move_is_not_shifted
    game = PGN::Game.new
    game.moves << PGN::Move.new('e4')
    game.moves << PGN::Move.new('e5', ['$201']) # $201 on the last move
    @editor.shift_critical_annotations(game)
    assert_nil game.moves[0].annotation
    assert_equal ['$201'], game.moves[1].annotation, "$201 should remain on the last move if it's there"
  end
  
  def test_does_not_duplicate_201_if_already_present_on_next_move
    game = PGN::Game.new
    game.moves << PGN::Move.new('e4', ['$201'])
    game.moves << PGN::Move.new('e5', ['$201']) # Next move already has $201
    @editor.shift_critical_annotations(game)
    assert_nil game.moves[0].annotation
    assert_equal ['$201'], game.moves[1].annotation, "$201 should not be duplicated"
    assert_equal 1, game.moves[1].annotation.size
  end

  def test_complex_case_with_existing_annotations
    game = PGN::Game.new
    game.moves << PGN::Move.new('m1', ['$1', '$201']) # $201 to m2
    game.moves << PGN::Move.new('m2', ['$2'])         # m2 gets $201, keeps $2
    game.moves << PGN::Move.new('m3', ['$201'])       # $201 to m4
    game.moves << PGN::Move.new('m4', ['$3', '$201']) # m4 gets $201, keeps $3, $201 (no dupe)
    game.moves << PGN::Move.new('m5')                 # m5 starts off clean
    game.moves << PGN::Move.new('m6')                 # m6 should stay clean

    @editor.shift_critical_annotations(game)

    assert_equal ['$1'], game.moves[0].annotation
    assert_equal ['$2', '$201'].sort, game.moves[1].annotation.sort
    
    assert_nil game.moves[2].annotation
    assert_equal ['$3', '$201'].sort, game.moves[3].annotation.sort
    
    assert_equal ['$201'].sort, game.moves[4].annotation # This was m5 in the comment, which is index 4
    assert_nil game.moves[5].annotation # This was m6 in the comment, which is index 5
  end
end

# --- Tests for AppHelpers ---
class TestAppFindCriticalMomentHelper < Minitest::Test
  include AppHelpers # Make helper method available

  # Helper to create a mock PGN::Move object
  def mock_move(annotation_array = nil)
    move = PGN::Move.new('') # Notation doesn't matter for this helper
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
