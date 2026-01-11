# frozen_string_literal: true

require 'minitest/autorun'
require 'pgn'
require_relative '../lib/annotation_shifter'

class TestAnnotationShifter < Minitest::Test
  def setup
    @shifter = AnnotationShifter.new
  end

  def test_no_moves
    game = PGN::Game.new([])
    @shifter.shift_critical_annotations(game)

    assert_empty game.moves
  end

  def test_one_move_with_annotation
    game = PGN::Game.new([PGN::MoveText.new('e4', ['$201'])])
    @shifter.shift_critical_annotations(game)

    assert_equal ['$201'], game.moves[0].annotation, 'Annotation should remain on the only move'
  end

  def test_shifts_201_to_next_move
    game = PGN::Game.new([PGN::MoveText.new('e4', ['$201']), PGN::MoveText.new('e5')])
    @shifter.shift_critical_annotations(game)

    assert_nil game.moves[0].annotation, 'Annotation should be removed from the first move'
    assert_equal ['$201'], game.moves[1].annotation, 'Annotation should be added to the second move'
  end

  def test_shifts_201_when_next_move_has_annotations
    game = PGN::Game.new([PGN::MoveText.new('e4', ['$201']), PGN::MoveText.new('e5', ['$1'])])
    @shifter.shift_critical_annotations(game)

    assert_nil game.moves[0].annotation
    assert_includes game.moves[1].annotation, '$201'
    assert_includes game.moves[1].annotation, '$1'
    assert_equal 2, game.moves[1].annotation.size
  end

  def test_does_not_shift_other_annotations
    game = PGN::Game.new([PGN::MoveText.new('Nf3', ['$1', '$201']), PGN::MoveText.new('Nf6')])
    @shifter.shift_critical_annotations(game)

    assert_equal ['$1'], game.moves[0].annotation, 'Only $201 should be removed'
    assert_equal ['$201'], game.moves[1].annotation
  end

  def test_annotation_becomes_nil_if_201_was_only_one
    game = PGN::Game.new([PGN::MoveText.new('d4', ['$201']), PGN::MoveText.new('d5')])
    @shifter.shift_critical_annotations(game)

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
                         ])

    @shifter.shift_critical_annotations(game)

    assert_nil game.moves[0].annotation
    assert_equal ['$201'], game.moves[1].annotation

    assert_nil game.moves[2].annotation
    assert_equal ['$201'], game.moves[3].annotation

    assert_nil game.moves[4].annotation
  end

  def test_201_on_last_move_is_not_shifted
    game = PGN::Game.new([PGN::MoveText.new('e4'), PGN::MoveText.new('e5', ['$201'])])
    @shifter.shift_critical_annotations(game)

    assert_nil game.moves[0].annotation
    assert_equal ['$201'], game.moves[1].annotation, "$201 should remain on the last move if it's there"
  end

  def test_does_not_duplicate_201_if_already_present_on_next_move
    game = PGN::Game.new([PGN::MoveText.new('e4', ['$201']), PGN::MoveText.new('e5', ['$201'])])
    @shifter.shift_critical_annotations(game)

    assert_nil game.moves[0].annotation
    assert_equal ['$201'], game.moves[1].annotation, '$201 should not be duplicated'
    assert_equal 1, game.moves[1].annotation.size
  end

  def test_unshift_critical_annotations_reverses_shift
    game = PGN::Game.new([PGN::MoveText.new('e4'), PGN::MoveText.new('e5', ['$201'])])

    @shifter.unshift_critical_annotations(game)

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

    @shifter.unshift_critical_annotations(game)

    assert_equal ['$201'], game.moves[0].annotation
    assert_nil game.moves[1].annotation
    assert_equal ['$201'], game.moves[2].annotation
    assert_nil game.moves[3].annotation
  end

  def test_unshift_and_shift_round_trip
    game = PGN::Game.new([PGN::MoveText.new('e4', ['$201']), PGN::MoveText.new('e5')])
    original_state = game.moves[0].annotation&.dup

    @shifter.shift_critical_annotations(game)

    assert_nil game.moves[0].annotation
    assert_equal ['$201'], game.moves[1].annotation

    @shifter.unshift_critical_annotations(game)

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
                         ])

    @shifter.shift_critical_annotations(game)

    assert_equal ['$1'], game.moves[0].annotation
    assert_equal ['$2', '$201'].sort, game.moves[1].annotation.sort

    assert_nil game.moves[2].annotation
    assert_equal ['$3', '$201'].sort, game.moves[3].annotation.sort

    assert_equal ['$201'].sort, game.moves[4].annotation
    assert_nil game.moves[5].annotation
  end

  def test_add_201_to_move
    move = PGN::MoveText.new('e4')
    @shifter.add_201_to_move(move)

    assert_equal ['$201'], move.annotation
  end

  def test_add_201_to_move_with_existing_annotations
    move = PGN::MoveText.new('e4', ['$1'])
    @shifter.add_201_to_move(move)

    assert_includes move.annotation, '$201'
    assert_includes move.annotation, '$1'
    assert_equal 2, move.annotation.size
  end

  def test_add_201_to_move_does_not_duplicate
    move = PGN::MoveText.new('e4', ['$201'])
    @shifter.add_201_to_move(move)

    assert_equal ['$201'], move.annotation
    assert_equal 1, move.annotation.size
  end
end
