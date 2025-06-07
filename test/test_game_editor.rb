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
    attr_accessor :moves, :tags, :positions # Added positions

    def initialize
      @moves = []
      @tags = {}
      @positions = [] # Initialize positions
    end
  end

  # Mock for PGN::Position to be used in tests
  class Position
    attr_reader :internal_fen_value

    def initialize(fen_string)
      @internal_fen_value = fen_string
    end

    # Mocks the behavior of PGN::Position#to_fen, which returns a PGN::FEN object.
    # That PGN::FEN object then has a #to_s method.
    def to_fen
      fen_mock = Object.new
      # Define #to_s on the fly for our PGN::FEN mock
      fen_mock.define_singleton_method(:to_s) { @internal_fen_value }
      fen_mock
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

# --- Tests for AppHelpers#get_last_move_info ---
class TestAppGetLastMoveInfoHelper < Minitest::Test
  include AppHelpers # Make get_last_move_info available

  def setup
    @game = PGN::Game.new # Uses our mock PGN::Game
    # Populate with mock PGN::Position and PGN::Move objects
    # Positions: initial_fen, fen_after_move1, fen_after_move2, ...
    @game.positions = [
      PGN::Position.new("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"), # Initial
      PGN::Position.new("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"),   # After 1. e4
      PGN::Position.new("rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2"), # After 1... d5
      PGN::Position.new("rnbqkbnr/ppp1pppp/8/3p4/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2")  # After 2. Nf3
    ]

    # Moves: 1. e4, 1... d5, 2. Nf3
    @game.moves = [
      PGN::Move.new('e4'),
      PGN::Move.new('d5', ['$1']), # Black's move with an annotation
      PGN::Move.new('Nf3', nil, 'A comment') # White's move with a comment
    ]
    # Add variations for critical moment testing if needed by get_last_move_info
    # For now, focusing on number, turn, san, comment, annotation
    critical_move_with_variation = PGN::Move.new('Qh5', ['$201'])
    var_move = PGN::Move.new('Nf6')
    critical_move_with_variation.variations << [var_move]
    @game.moves << critical_move_with_variation # 2... Qh5 (critical)
    @game.positions << PGN::Position.new("rnb1kbnr/ppp1pppp/8/3p3Q/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3") # After 2... Qh5
  end

  def test_get_last_move_info_at_start_of_game
    assert_nil get_last_move_info(@game, 0), "Should be nil for position index 0"
  end

  def test_get_last_move_info_for_whites_first_move
    info = get_last_move_info(@game, 1) # After 1. e4 (move index 0)
    assert_equal 1, info[:number], "Move number for White's 1st move"
    assert_equal 'white', info[:turn], "Turn for White's 1st move"
    assert_equal 'e4', info[:san], "SAN for White's 1st move"
    assert_nil info[:comment]
    assert_nil info[:annotation]
    assert_equal "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", info[:fen_before_move]
  end

  def test_get_last_move_info_for_blacks_first_move
    info = get_last_move_info(@game, 2) # After 1... d5 (move index 1)
    assert_equal 1, info[:number], "Move number for Black's 1st move"
    assert_equal 'black', info[:turn], "Turn for Black's 1st move"
    assert_equal 'd5', info[:san], "SAN for Black's 1st move"
    assert_equal ['$1'], info[:annotation]
    assert_equal "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", info[:fen_before_move]
  end

  def test_get_last_move_info_for_whites_second_move
    info = get_last_move_info(@game, 3) # After 2. Nf3 (move index 2)
    assert_equal 2, info[:number], "Move number for White's 2nd move"
    assert_equal 'white', info[:turn], "Turn for White's 2nd move"
    assert_equal 'Nf3', info[:san], "SAN for White's 2nd move"
    assert_equal 'A comment', info[:comment]
    assert_equal "rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2", info[:fen_before_move]
  end
  
  def test_get_last_move_info_for_critical_move_with_variation
    info = get_last_move_info(@game, 4) # After 2... Qh5 (move index 3, critical)
    assert_equal 2, info[:number], "Move number for Black's 2nd move (critical)"
    assert_equal 'black', info[:turn], "Turn for Black's 2nd move (critical)"
    assert_equal 'Qh5', info[:san], "SAN for Black's 2nd move (critical)"
    assert_equal ['$201'], info[:annotation]
    assert_equal true, info[:is_critical]
    assert_equal 'Nf6', info[:good_move_san] # From variation
    assert_equal "rnbqkbnr/ppp1pppp/8/3p4/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2", info[:fen_before_move]
  end

  def test_get_last_move_info_with_nil_game
    assert_nil get_last_move_info(nil, 1), "Should be nil if game is nil"
  end

  def test_get_last_move_info_with_empty_moves
    empty_game = PGN::Game.new
    empty_game.positions = [PGN::Position.new("fen_initial")]
    assert_nil get_last_move_info(empty_game, 1), "Should be nil if game has no moves but position index > 0"
  end
  
  def test_get_last_move_info_index_out_of_bounds
    # current_position_index too high for moves array
    assert_nil get_last_move_info(@game, @game.moves.size + 2), "Index out of bounds for moves"
    # current_position_index too high for positions array (for fen_before_move)
    # This case is tricky because actual_move_index_in_game_array might be valid for moves
    # but not for positions. Let's ensure positions has one less element than moves for this.
    game_short_pos = PGN::Game.new
    game_short_pos.moves = [PGN::Move.new('e4')]
    game_short_pos.positions = [PGN::Position.new("fen_initial")] # Only initial, no pos after e4
    assert_nil get_last_move_info(game_short_pos, 1), "Index out of bounds for positions"
  end
end
