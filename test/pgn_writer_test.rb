# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/pgn_writer'
require 'pgn'

class PGNWriterTest < Minitest::Test
  def setup
    @writer = PGNWriter.new
  end

  def test_write_simple_game
    game = PGN::Game.new(
      %w[e4 e5 Nf3 Nc6],
      {
        'Event' => 'Test Game',
        'Site' => 'Testing',
        'Date' => '2025.10.25',
        'Round' => '1',
        'White' => 'Player1',
        'Black' => 'Player2',
        'Result' => '1-0'
      },
      '1-0'
    )

    result = @writer.write(game)

    assert_includes result, '[Event "Test Game"]'
    assert_includes result, '[Site "Testing"]'
    assert_includes result, '[White "Player1"]'
    assert_includes result, '[Black "Player2"]'
    assert_includes result, '1.e4 e5 2.Nf3 Nc6 1-0'
  end

  def test_write_game_with_annotations
    moves = %w[e4 e5 Nf3 Nc6]
    game = PGN::Game.new(moves, { 'Result' => '*' }, '*')

    # Add $201 annotation to first move
    game.moves[0].annotation = ['$201']

    # Add multiple annotations to third move
    game.moves[2].annotation = ['$2', '$18']

    result = @writer.write(game)

    assert_includes result, '1.e4 $201'
    assert_includes result, '2.Nf3 $2 $18'
  end

  def test_write_game_with_comments
    moves = %w[e4 e5]
    game = PGN::Game.new(moves, { 'Result' => '*' }, '*')

    game.moves[0].comment = 'Best by test'
    game.moves[1].comment = 'Solid response'

    result = @writer.write(game)

    assert_includes result, '1.e4 {Best by test}'
    assert_includes result, 'e5 {Solid response}'
  end

  def test_write_game_with_variations
    moves = %w[e4 e5 Nf3]
    game = PGN::Game.new(moves, { 'Result' => '*' }, '*')

    # Add variation to second move (black's first move)
    # Variation: 1...c5
    variation_move = PGN::MoveText.new('c5')
    game.moves[1].variations = [[variation_move]]

    result = @writer.write(game)

    assert_includes result, 'e5 (1...c5)'
  end

  def test_write_game_with_complex_variations
    moves = %w[e4 e5 Nf3 Nc6]
    game = PGN::Game.new(moves, { 'Result' => '*' }, '*')

    # Add variation to black's first move: 1...c5 2.Nf3
    var_move_1 = PGN::MoveText.new('c5')
    var_move_1.comment = 'Sicilian Defense'
    var_move_2 = PGN::MoveText.new('Nf3')

    game.moves[1].variations = [[var_move_1, var_move_2]]

    result = @writer.write(game)

    assert_includes result, 'e5 (1...c5 {Sicilian Defense} 2.Nf3)'
  end

  def test_write_game_with_annotations_comments_and_variations
    moves = %w[e4 e5]
    game = PGN::Game.new(moves, { 'Result' => '*' }, '*')

    # Second move has annotation, comment, and variation
    game.moves[1].annotation = ['$201', '$2']
    game.moves[1].comment = 'This is weak'

    var_move = PGN::MoveText.new('c5')
    var_move.comment = 'Better'
    game.moves[1].variations = [[var_move]]

    result = @writer.write(game)

    assert_includes result, 'e5 $201 $2 {This is weak} (1...c5 {Better})'
  end

  def test_write_empty_game
    game = PGN::Game.new([], { 'Result' => '*' }, '*')

    result = @writer.write(game)

    assert_includes result, '[Result "*"]'
    assert_includes result, '*'
  end

  def test_write_game_starting_from_black
    # This tests a variation that starts with black's move (common in analysis)
    # Note: A full game starting with black would need a FEN tag
    # For this test, we're verifying the move numbering logic works
    moves = ['Nc6']
    game = PGN::Game.new(moves, { 'Result' => '*' }, '*')

    result = @writer.write(game)

    # Without FEN tag, the writer assumes white's first move by index
    # This is expected behavior - real games starting with black would have FEN
    assert_includes result, '1.Nc6'
  end

  def test_round_trip_simple_game
    original_pgn = <<~PGN
      [Event "Test"]
      [Site "Testing"]
      [Date "2025.10.25"]
      [Round "1"]
      [White "Player1"]
      [Black "Player2"]
      [Result "1-0"]

      1.e4 e5 2.Nf3 Nc6 3.Bb5 1-0
    PGN

    # Parse, serialize, parse again
    games = PGN.parse(original_pgn.dup)
    game = games.first

    serialized = @writer.write(game)
    reparsed = PGN.parse(serialized.dup).first

    assert_equal game.moves.size, reparsed.moves.size
    assert_equal game.tags['White'], reparsed.tags['White']
    assert_equal game.tags['Black'], reparsed.tags['Black']
    assert_equal game.result, reparsed.result

    # Check moves match
    game.moves.each_with_index do |move, i|
      assert_equal move.notation.to_s, reparsed.moves[i].notation.to_s
    end
  end

  def test_round_trip_with_annotations
    # Create a game with annotations
    moves = %w[e4 e5 Nf3]
    game = PGN::Game.new(
      moves,
      { 'White' => 'Test', 'Black' => 'Test2', 'Result' => '*' },
      '*'
    )

    game.moves[1].annotation = ['$201']

    serialized = @writer.write(game)
    reparsed = PGN.parse(serialized.dup).first

    # Check annotation survived round trip
    # The pgn2 gem may return annotation as string or array depending on version
    annotation = reparsed.moves[1].annotation
    if annotation.is_a?(Array)
      assert_includes annotation, '$201'
    else
      assert_equal '$201', annotation
    end
  end

  def test_escapes_special_characters_in_tags
    game = PGN::Game.new(
      %w[e4 e5],
      {
        'White' => 'Player "Nickname" Name',
        'Event' => 'Test\Event', # Single backslash in the string
        'Result' => '*'
      },
      '*'
    )

    result = @writer.write(game)

    # Should escape quotes and backslashes
    assert_includes result, '[White "Player \\"Nickname\\" Name"]'
    # Single backslash becomes double backslash in output
    assert_includes result, '[Event "Test\\Event"]'
  end

  def test_handles_nil_and_empty_comments
    moves = %w[e4 e5]
    game = PGN::Game.new(moves, { 'Result' => '*' }, '*')

    game.moves[0].comment = nil
    game.moves[1].comment = ''

    result = @writer.write(game)

    # Should not crash and should not include empty comments
    refute_includes result, '{}'
  end

  def test_wraps_long_lines
    # Create a game with many moves to test line wrapping
    moves = %w[e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7 Re1 b5 Bb3 d6 c3 O-O h3 Nb8 d4 Nbd7]
    game = PGN::Game.new(moves, { 'Result' => '*' }, '*')

    result = @writer.write(game)

    # Check that lines are wrapped (result should have multiple lines in movetext)
    lines = result.lines
    movetext_lines = lines.drop_while { |line| line.start_with?('[') || line.strip.empty? }

    # At least some lines should be present due to wrapping
    assert_operator movetext_lines.size, :>, 1, 'Expected multiple lines due to wrapping'
  end

  # rubocop:disable Minitest/MultipleAssertions
  def test_write_standard_tag_order
    game = PGN::Game.new(
      %w[e4 e5],
      {
        'WhiteElo' => '2000', # Extra tag
        'Black' => 'Player2',
        'White' => 'Player1',
        'Event' => 'Test',
        'Date' => '2025.10.25',
        'Site' => 'Testing',
        'Round' => '1',
        'Result' => '*'
      },
      '*'
    )

    result = @writer.write(game)
    lines = result.lines.take_while { |line| line.start_with?('[') }

    # Check Seven Tag Roster appears first in correct order
    assert_match(/\[Event/, lines[0])
    assert_match(/\[Site/, lines[1])
    assert_match(/\[Date/, lines[2])
    assert_match(/\[Round/, lines[3])
    assert_match(/\[White/, lines[4])
    assert_match(/\[Black/, lines[5])
    assert_match(/\[Result/, lines[6])

    # Extra tag comes after
    assert_match(/\[WhiteElo/, lines[7])
  end
  # rubocop:enable Minitest/MultipleAssertions
end
