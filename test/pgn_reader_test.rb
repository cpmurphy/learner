# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/pgn_reader'

class PGNReaderTest < Minitest::Test
  def setup
    @reader = PGNReader.new
  end

  def test_read_simple_game
    pgn_text = <<~PGN
      [Event "Test"]
      [White "Player1"]
      [Black "Player2"]
      [Result "1-0"]

      1.e4 e5 2.Nf3 Nc6 1-0
    PGN

    games = @reader.read(pgn_text.dup)

    assert_equal 1, games.size

    game = games.first

    assert_equal 'Player1', game.tags['White']
    assert_equal 'Player2', game.tags['Black']
    assert_equal '1-0', game.result
    assert_equal 4, game.moves.size
  end

  def test_read_multiple_games
    pgn_text = <<~PGN
      [Event "Game 1"]
      [Result "1-0"]

      1.e4 e5 1-0

      [Event "Game 2"]
      [Result "0-1"]

      1.d4 d5 0-1
    PGN

    games = @reader.read(pgn_text.dup)

    assert_equal 2, games.size
    assert_equal 'Game 1', games[0].tags['Event']
    assert_equal 'Game 2', games[1].tags['Event']
  end

  def test_read_game_with_annotations
    pgn_text = <<~PGN
      [Result "*"]

      1.e4 $201 e5 2.Nf3 *
    PGN

    games = @reader.read(pgn_text.dup)
    game = games.first
    annotation = game.moves[0].annotation
    if annotation.is_a?(Array)
      assert_includes annotation, '$201'
    else
      assert_equal '$201', annotation
    end
  end

  def test_read_game_with_comments
    pgn_text = <<~PGN
      [Result "*"]

      1.e4 {Best by test} e5 {Solid response} *
    PGN

    games = @reader.read(pgn_text.dup)
    game = games.first

    assert_equal 'Best by test', game.moves[0].comment
    assert_equal 'Solid response', game.moves[1].comment
  end

  def test_read_game_with_variations
    pgn_text = <<~PGN
      [Result "*"]

      1.e4 e5 (1...c5 2.Nf3) 2.Nf3 *
    PGN

    games = @reader.read(pgn_text.dup)
    game = games.first
    variations = game.moves[1].variations

    refute_nil variations
    refute_empty variations
    assert_equal 'c5', variations[0][0].notation.to_s
  end

  def test_read_game_missing_result_termination_with_result_tag
    pgn_text = <<~PGN
      [Event "Test"]
      [Result "1-0"]

      1.e4 e5 2.Nf3 Nc6
    PGN

    games = @reader.read(pgn_text.dup)

    assert_equal 1, games.size
    assert_equal '1-0', games.first.result
  end

  def test_read_game_missing_result_termination_draw
    pgn_text = <<~PGN
      [Result "1/2-1/2"]

      1.e4 e5
    PGN

    games = @reader.read(pgn_text.dup)

    assert_equal '1/2-1/2', games.first.result
  end

  def test_read_game_missing_result_termination_ongoing
    pgn_text = <<~PGN
      [Result "*"]

      1.e4 e5
    PGN

    games = @reader.read(pgn_text.dup)

    assert_equal '*', games.first.result
  end

  def test_read_game_with_result_termination_present
    pgn_text = <<~PGN
      [Result "0-1"]

      1.e4 e5 0-1
    PGN

    games = @reader.read(pgn_text.dup)

    assert_equal '0-1', games.first.result
  end

  def test_read_empty_string
    games = @reader.read(+'')

    assert_empty games
  end

  def test_read_nil
    games = @reader.read(nil)

    assert_empty games
  end

  def test_read_real_pgn_file
    pgn_content = File.read('test/data/cagnus-marlsen-no-alt.pgn')
    games = @reader.read(pgn_content)

    assert_equal 1, games.size

    game = games.first

    assert_equal 'Cagnus Marlsen', game.tags['White']
    assert_equal 'Player', game.tags['Black']
    assert_equal '1-0', game.result
  end

  def test_read_game_with_no_result_tag_raises_parse_error
    pgn_text = <<~PGN
      [Event "Test"]

      1.e4 e5
    PGN

    assert_raises(Whittle::ParseError) { @reader.read(pgn_text.dup) }
  end

  def test_read_game_with_invalid_result_tag_raises_parse_error
    pgn_text = <<~PGN
      [Result "invalid"]

      1.e4 e5
    PGN

    assert_raises(Whittle::ParseError) { @reader.read(pgn_text.dup) }
  end

  def test_ensure_pgn_has_result_termination_returns_nil_for_nil
    result = @reader.send(:ensure_pgn_has_result_termination, nil)

    assert_nil result
  end

  def test_ensure_pgn_has_result_termination_returns_empty_for_empty
    result = @reader.send(:ensure_pgn_has_result_termination, '')

    assert_equal '', result
  end

  def test_ensure_pgn_has_result_termination_appends_result
    pgn_text = "[Result \"1-0\"]\n\n1.e4 e5"
    result = @reader.send(:ensure_pgn_has_result_termination, pgn_text)

    assert_match(/1-0\s*\z/, result)
  end

  def test_ensure_pgn_has_result_termination_does_not_duplicate
    pgn_text = "[Result \"1-0\"]\n\n1.e4 e5 1-0"
    result = @reader.send(:ensure_pgn_has_result_termination, pgn_text)

    assert_match(/1-0\s*\z/, result)
    refute_match(/1-0\s+1-0\s*\z/, result)
  end

  def test_ensure_pgn_has_result_termination_black_wins
    pgn_text = "[Result \"0-1\"]\n\n1.e4 e5"
    result = @reader.send(:ensure_pgn_has_result_termination, pgn_text)

    assert result.rstrip.end_with?('0-1')
  end

  def test_parses_pgns_with_emoji
    pgn_text = <<~PGN
      [Event "Test"]
      [White "Player1"]
      [Black "Player2"]
      [Result "1-0"]

      1.e4 { best by test… 👉😭👈} 1... e5 2.Nf3 Nc6 1-0
    PGN

    games = @reader.read(pgn_text.dup)

    assert_equal 1, games.size

    game = games.first

    assert_equal 'Player1', game.tags['White']
  end
end
