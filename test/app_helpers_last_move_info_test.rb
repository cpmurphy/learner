# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/mock'
require 'pgn' # Gem for PGN parsing, used to construct test objects
require_relative '../lib/app_helpers' # For testing AppHelpers module

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

  def test_build_move_info_hash_includes_centipawn_loss
    move = PGN::MoveText.new('e4', nil, 'cp_loss: 75')
    game = PGN::Game.new([move])

    info = build_move_info_hash(move, 0, game)

    assert_equal 75, info[:centipawn_loss]
  end

  def test_build_move_info_hash_handles_missing_centipawn_loss
    move = PGN::MoveText.new('e4', nil, 'No cp_loss')
    game = PGN::Game.new([move])

    info = build_move_info_hash(move, 0, game)

    assert_nil info[:centipawn_loss]
  end
end
