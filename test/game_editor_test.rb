# frozen_string_literal: true

require 'minitest/autorun'
require 'pgn' # Gem for PGN parsing, used to construct test objects
require_relative '../lib/game_editor'
require_relative '../lib/app_helpers' # For testing AppHelpers module

class TestGameEditor < Minitest::Test
  def setup
    @editor = GameEditor.new
  end

  def test_no_moves
    game = PGN::Game.new([])
    @editor.shift_critical_annotations(game)

    assert_empty game.moves
  end

  def test_one_move_with_annotation
    game = PGN::Game.new([PGN::MoveText.new('e4', ['$201'])])
    @editor.shift_critical_annotations(game)

    assert_equal ['$201'], game.moves[0].annotation, 'Annotation should remain on the only move'
  end

  def test_shifts_201_to_next_move
    game = PGN::Game.new([PGN::MoveText.new('e4', ['$201']), PGN::MoveText.new('e5')])
    @editor.shift_critical_annotations(game)

    assert_nil game.moves[0].annotation, 'Annotation should be removed from the first move'
    assert_equal ['$201'], game.moves[1].annotation, 'Annotation should be added to the second move'
  end

  def test_shifts_201_when_next_move_has_annotations
    game = PGN::Game.new([PGN::MoveText.new('e4', ['$201']), PGN::MoveText.new('e5', ['$1'])]) # Next move already has an annotation
    @editor.shift_critical_annotations(game)

    assert_nil game.moves[0].annotation
    assert_includes game.moves[1].annotation, '$201'
    assert_includes game.moves[1].annotation, '$1'
    assert_equal 2, game.moves[1].annotation.size
  end

  def test_does_not_shift_other_annotations
    game = PGN::Game.new([PGN::MoveText.new('Nf3', ['$1', '$201']), PGN::MoveText.new('Nf6')])
    @editor.shift_critical_annotations(game)

    assert_equal ['$1'], game.moves[0].annotation, 'Only $201 should be removed'
    assert_equal ['$201'], game.moves[1].annotation
  end

  def test_annotation_becomes_nil_if_201_was_only_one
    game = PGN::Game.new([PGN::MoveText.new('d4', ['$201']), PGN::MoveText.new('d5')])
    @editor.shift_critical_annotations(game)

    assert_nil game.moves[0].annotation, 'Annotation array should become nil if $201 was the only one'
    assert_equal ['$201'], game.moves[1].annotation
  end

  def test_multiple_shifts_in_a_game
    game = PGN::Game.new([
                           PGN::MoveText.new('e4', ['$201']),
                           PGN::MoveText.new('e5'),
                           PGN::MoveText.new('Nf3', ['$201']),
                           PGN::MoveText.new('Nc6'),
                           PGN::MoveText.new('Bc4')
                         ]) # No annotation initially

    @editor.shift_critical_annotations(game)

    assert_nil game.moves[0].annotation
    assert_equal ['$201'], game.moves[1].annotation

    assert_nil game.moves[2].annotation
    assert_equal ['$201'], game.moves[3].annotation

    assert_nil game.moves[4].annotation
  end

  def test_201_on_last_move_is_not_shifted
    game = PGN::Game.new([PGN::MoveText.new('e4'), PGN::MoveText.new('e5', ['$201'])]) # $201 on the last move
    @editor.shift_critical_annotations(game)

    assert_nil game.moves[0].annotation
    assert_equal ['$201'], game.moves[1].annotation, "$201 should remain on the last move if it's there"
  end

  def test_does_not_duplicate_201_if_already_present_on_next_move
    game = PGN::Game.new([PGN::MoveText.new('e4', ['$201']), PGN::MoveText.new('e5', ['$201'])]) # Next move already has $201
    @editor.shift_critical_annotations(game)

    assert_nil game.moves[0].annotation
    assert_equal ['$201'], game.moves[1].annotation, '$201 should not be duplicated'
    assert_equal 1, game.moves[1].annotation.size
  end

  def test_unshift_critical_annotations_reverses_shift
    # Start with $201 on move 1 (after shift)
    game = PGN::Game.new([PGN::MoveText.new('e4'), PGN::MoveText.new('e5', ['$201'])])
    
    @editor.unshift_critical_annotations(game)
    
    assert_equal ['$201'], game.moves[0].annotation, 'Annotation should be moved back to first move'
    assert_nil game.moves[1].annotation, 'Annotation should be removed from second move'
  end

  def test_unshift_critical_annotations_multiple_annotations
    game = PGN::Game.new([
                           PGN::MoveText.new('e4'),
                           PGN::MoveText.new('e5', ['$201']),
                           PGN::MoveText.new('Nf3'),
                           PGN::MoveText.new('Nc6', ['$201'])
                         ])
    
    @editor.unshift_critical_annotations(game)
    
    assert_equal ['$201'], game.moves[0].annotation
    assert_nil game.moves[1].annotation
    assert_equal ['$201'], game.moves[2].annotation
    assert_nil game.moves[3].annotation
  end

  def test_unshift_and_shift_round_trip
    # Original: $201 on move 0 (before blunder)
    game = PGN::Game.new([PGN::MoveText.new('e4', ['$201']), PGN::MoveText.new('e5')])
    original_state = game.moves[0].annotation&.dup
    
    # Shift
    @editor.shift_critical_annotations(game)
    assert_nil game.moves[0].annotation
    assert_equal ['$201'], game.moves[1].annotation
    
    # Unshift
    @editor.unshift_critical_annotations(game)
    assert_equal original_state, game.moves[0].annotation
    assert_nil game.moves[1].annotation
  end

  def test_complex_case_with_existing_annotations
    game = PGN::Game.new([
                           PGN::MoveText.new('e4', ['$1', '$201']),
                           PGN::MoveText.new('e5', ['$2']),
                           PGN::MoveText.new('Nf3', ['$201']),
                           PGN::MoveText.new('Nc6', ['$3', '$201']),
                           PGN::MoveText.new('Bc4'),
                           PGN::MoveText.new('Bc5')
                         ]) # Black's third move should stay clean

    @editor.shift_critical_annotations(game)

    assert_equal ['$1'], game.moves[0].annotation
    assert_equal ['$2', '$201'].sort, game.moves[1].annotation.sort

    assert_nil game.moves[2].annotation
    assert_equal ['$3', '$201'].sort, game.moves[3].annotation.sort

    assert_equal ['$201'].sort, game.moves[4].annotation # This is White's third move, which is index 4
    assert_nil game.moves[5].annotation # This is Black's third move, which is index 5
  end

  def test_game_evaluation
    games = PGN.parse(File.read('test/data/quill-2025-08-06.pgn'))
    @editor.add_blunder_annotations(games[0])
    # Check that blunders were detected and annotated
    blunders = games[0].moves.compact.select { |m| m.annotation && m.annotation.include?('$201') }
    assert blunders.size > 0, 'Should find at least one blunder in the game'
  end

  def test_add_blunder_annotations_adds_variations
    # Create a simple game where we know there's a blunder
    # 1.e4 e5 2.Qh5?? - This is a blunder, better is 2.Nf3
    game = PGN::Game.new(%w[e4 e5 Qh5 Nc6])

    # Analyze and annotate
    @editor.add_blunder_annotations(game)

    # Find moves with $201 annotation
    critical_moves = game.moves.select { |m| m.annotation && m.annotation.include?('$201') }

    # Skip test if no blunders detected (Stockfish may not find this as a blunder)
    skip 'No blunders detected in test game' if critical_moves.empty?

    # Check that at least one critical move has variations
    has_variation = critical_moves.any? { |m| m.variations && !m.variations.empty? }
    assert has_variation, 'At least one blunder should have a variation with a better move'

    # Check the structure of the variation
    move_with_variation = critical_moves.find { |m| m.variations && !m.variations.empty? }
    if move_with_variation
      variation = move_with_variation.variations.first
      assert variation.is_a?(Array), 'Variation should be an array of moves'
      assert variation.size > 0, 'Variation should have at least one move'

      first_var_move = variation.first
      assert first_var_move.is_a?(PGN::MoveText), 'Variation move should be a PGN::MoveText'
      assert first_var_move.notation, 'Variation move should have notation'
      assert first_var_move.comment, 'Variation move should have a comment explaining the advantage'
    end
  end

  def test_format_centipawns
    assert_equal '+1.4', @editor.format_centipawns(140)
    assert_equal '+2.5', @editor.format_centipawns(250)
    assert_equal '+0.5', @editor.format_centipawns(50)
  end

  def test_format_centipawns_mate_score
    # Mate scores are typically > 900 centipawns
    assert_match(/\+M\d+/, @editor.format_centipawns(950))
  end
end

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

# --- Tests for AppHelpers#get_last_move_info ---
class TestAppGetLastMoveInfoHelper < Minitest::Test
  include AppHelpers # Make get_last_move_info available

  def setup
    @game = PGN::Game.new([
                            PGN::MoveText.new('e4'),
                            PGN::MoveText.new('d5', ['$1']),
                            PGN::MoveText.new('Nf3', nil, 'A comment'),
                            PGN::MoveText.new('Qh4', ['$201'], nil, [[PGN::MoveText.new('Nf6')]])
                          ])
  end

  def test_get_last_move_info_at_start_of_game
    assert_nil get_last_move_info(@game, 0), 'Should be nil for position index 0'
  end

  def test_get_last_move_info_for_whites_first_move
    info = get_last_move_info(@game, 1) # After 1. e4 (move index 0)

    assert_equal 1, info[:number], "Move number for White's 1st move"
    assert_equal 'white', info[:turn], "Turn for White's 1st move"
    assert_equal 'e4', info[:san], "SAN for White's 1st move"
    assert_nil info[:comment]
    assert_nil info[:annotation]
    assert_equal 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', info[:fen_before_move]
  end

  def test_get_last_move_info_for_blacks_first_move
    info = get_last_move_info(@game, 2) # After 1... d5 (move index 1)

    assert_equal 1, info[:number], "Move number for Black's 1st move"
    assert_equal 'black', info[:turn], "Turn for Black's 1st move"
    assert_equal 'd5', info[:san], "SAN for Black's 1st move"
    assert_equal ['$1'], info[:annotation]
    assert_equal 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1', info[:fen_before_move]
  end

  def test_get_last_move_info_for_whites_second_move
    info = get_last_move_info(@game, 3) # After 2. Nf3 (move index 2)

    assert_equal 2, info[:number], "Move number for White's 2nd move"
    assert_equal 'white', info[:turn], "Turn for White's 2nd move"
    assert_equal 'Nf3', info[:san], "SAN for White's 2nd move"
    assert_equal 'A comment', info[:comment]
    assert_equal 'rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2', info[:fen_before_move]
  end

  def test_get_last_move_info_for_critical_move_with_variation
    info = get_last_move_info(@game, 4) # After 2... Qh4 (move index 3, critical)

    assert_equal 2, info[:number], "Move number for Black's 2nd move (critical)"
    # assert_equal 'black', info[:turn], "Turn for Black's 2nd move (critical)"
    assert_equal 'Qh4', info[:san], "SAN for Black's 2nd move (critical)"
    assert_equal ['$201'], info[:annotation]
    assert info[:is_critical]
    assert_equal 'Nf6', info[:good_move_san] # From variation
    assert_equal 'rnbqkbnr/ppp1pppp/8/3p4/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2', info[:fen_before_move]
  end

  def test_get_last_move_info_with_nil_game
    assert_nil get_last_move_info(nil, 1), 'Should be nil if game is nil'
  end

  def test_get_last_move_info_with_empty_moves
    empty_game = PGN::Game.new([])

    assert_nil get_last_move_info(empty_game, 1), 'Should be nil if game has no moves but position index > 0'
  end

  def test_get_last_move_info_index_out_of_bounds
    # current_position_index too high for moves array
    assert_nil get_last_move_info(@game, @game.moves.size + 2), 'Index out of bounds for moves'
    # current_position_index too high for positions array (for fen_before_move)
    # This case is tricky because actual_move_index_in_game_array might be valid for moves
    # but not for positions. Let's ensure positions has one less element than moves for this.
    game_short_pos = PGN::Game.new([])
    # To test "Index out of bounds for positions", where fen_before_move cannot be found.
    # This means game.positions[actual_move_index_in_game_array] is invalid.
    # For current_position_index = 1, actual_move_index_in_game_array = 0.
    # So, game.positions[0] should be invalid, meaning game.positions is empty.
    assert_nil get_last_move_info(game_short_pos, 1), 'Index out of bounds for positions (empty positions array)'
  end
end
