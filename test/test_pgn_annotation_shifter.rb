# frozen_string_literal: true

require 'minitest/autorun'
require 'pgn' # Gem for PGN parsing, used to construct test objects
require_relative '../lib/pgn_annotation_shifter'

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

class TestPgnAnnotationShifter < Minitest::Test
  def setup
    @shifter = PgnAnnotationShifter
  end

  def test_no_moves
    game = PGN::Game.new
    @shifter.shift_critical_annotations(game)
    assert_empty game.moves
  end

  def test_one_move_with_annotation
    game = PGN::Game.new
    game.moves << PGN::Move.new('e4', ['$201'])
    @shifter.shift_critical_annotations(game)
    assert_equal ['$201'], game.moves[0].annotation, "Annotation should remain on the only move"
  end

  def test_shifts_201_to_next_move
    game = PGN::Game.new
    game.moves << PGN::Move.new('e4', ['$201'])
    game.moves << PGN::Move.new('e5')
    @shifter.shift_critical_annotations(game)
    assert_nil game.moves[0].annotation, "Annotation should be removed from the first move"
    assert_equal ['$201'], game.moves[1].annotation, "Annotation should be added to the second move"
  end

  def test_shifts_201_when_next_move_has_annotations
    game = PGN::Game.new
    game.moves << PGN::Move.new('e4', ['$201'])
    game.moves << PGN::Move.new('e5', ['$1']) # Next move already has an annotation
    @shifter.shift_critical_annotations(game)
    assert_nil game.moves[0].annotation
    assert_includes game.moves[1].annotation, '$201'
    assert_includes game.moves[1].annotation, '$1'
    assert_equal 2, game.moves[1].annotation.size
  end

  def test_does_not_shift_other_annotations
    game = PGN::Game.new
    game.moves << PGN::Move.new('Nf3', ['$1', '$201'])
    game.moves << PGN::Move.new('Nf6')
    @shifter.shift_critical_annotations(game)
    assert_equal ['$1'], game.moves[0].annotation, "Only $201 should be removed"
    assert_equal ['$201'], game.moves[1].annotation
  end

  def test_annotation_becomes_nil_if_201_was_only_one
    game = PGN::Game.new
    game.moves << PGN::Move.new('d4', ['$201'])
    game.moves << PGN::Move.new('d5')
    @shifter.shift_critical_annotations(game)
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

    @shifter.shift_critical_annotations(game)

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
    @shifter.shift_critical_annotations(game)
    assert_nil game.moves[0].annotation
    assert_equal ['$201'], game.moves[1].annotation, "$201 should remain on the last move if it's there"
  end
  
  def test_does_not_duplicate_201_if_already_present_on_next_move
    game = PGN::Game.new
    game.moves << PGN::Move.new('e4', ['$201'])
    game.moves << PGN::Move.new('e5', ['$201']) # Next move already has $201
    @shifter.shift_critical_annotations(game)
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
    game.moves << PGN::Move.new('m5')                 # m5 is clean

    @shifter.shift_critical_annotations(game)

    assert_equal ['$1'], game.moves[0].annotation
    assert_equal ['$2', '$201'].sort, game.moves[1].annotation.sort
    
    assert_nil game.moves[2].annotation
    assert_equal ['$3', '$201'].sort, game.moves[3].annotation.sort
    
    assert_nil game.moves[4].annotation
  end
end
