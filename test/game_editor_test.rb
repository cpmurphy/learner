# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/mock'
require 'pgn' # Gem for PGN parsing, used to construct test objects
require_relative '../lib/game_editor'
require_relative '../lib/move_translator'
require_relative '../lib/app_helpers' # For testing AppHelpers module

class TestGameEditor < Minitest::Test
  def setup
    @editor = GameEditor.new
  end

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def test_game_evaluation
    games = PGN.parse(File.read('test/data/quill-2025-08-06.pgn'))
    game = games[0]

    # Mock the Analyzer to avoid slow Stockfish calls
    mock_analyzer = Minitest::Mock.new
    translator = MoveTranslator.new

    # For each move, we need to mock evaluate_best_move and evaluate_move
    (0...game.moves.size).each do |i|
      next unless game.positions[i] && game.moves[i]

      # Setup mock expectations for this move
      fen = game.positions[i].to_fen.to_s

      # Translate the move that was played to UCI format
      translator.load_game_from_fen(fen)
      uci_move = translator.translate_move(game.moves[i].notation)

      # Build variation from the next 2 moves
      translator.load_game_from_fen(fen)
      variation = (i...(i + 2)).map do |j|
        break unless game.positions[j] && game.moves[j]

        translator.translate_move(game.moves[j].notation)
      end

      # Mock best move evaluation - return the move that was actually played
      mock_analyzer.expect :evaluate_best_move, { score: 200, move: uci_move, variation: variation }, [fen]

      # Mock played move evaluation - make every 3rd move a blunder (difference > 140)
      # Return a score that makes this a blunder: every 3rd move gets -200, others get 150
      played_score = (i % 3).zero? ? -200 : 150
      mock_analyzer.expect :evaluate_move, { score: played_score }, [fen, uci_move]
    end

    mock_analyzer.expect :close, nil

    Analyzer.stub :new, mock_analyzer do
      @editor.add_blunder_annotations(game)
    end

    # Check that blunders were detected and annotated
    blunders = game.moves.compact.select { |m| m.annotation&.include?('$201') }

    assert_predicate blunders.size, :positive?, 'Should find at least one blunder in the game'
    mock_analyzer.verify
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def test_add_blunder_annotations_adds_variations
    # Create a simple game where we know there's a blunder
    # 1.e4 e5 2.Qh5?? - This is a blunder, better is 2.Nf3
    game = PGN::Game.new(%w[e4 e5 Qh5 Nc6])

    # Mock the Analyzer to avoid slow Stockfish calls
    mock_analyzer = Minitest::Mock.new
    translator = MoveTranslator.new

    # Setup mock expectations for each move
    (0...game.moves.size).each do |i|
      next unless game.positions[i] && game.moves[i]

      fen = game.positions[i].to_fen.to_s
      translator.load_game_from_fen(fen)

      # Mock best move using the move actually played (simplified for testing)
      translator.load_game_from_fen(fen)
      uci_move = translator.translate_move(game.moves[i].notation)
      best_move_uci = uci_move

      # Mock variation to be moves actually played
      translator.load_game_from_fen(fen)
      variation = (i...(i + 2)).map do |j|
        break unless game.positions[j] && game.moves[j]

        translator.translate_move(game.moves[j].notation)
      end

      # Mock best move evaluation
      mock_analyzer.expect :evaluate_best_move,
                           { score: 200, move: best_move_uci, variation: variation },
                           [fen]

      # Mock played move evaluation - make move index 2 (Qh5) a blunder
      translator.load_game_from_fen(fen)
      uci_move = translator.translate_move(game.moves[i].notation)
      played_score = i == 2 ? -200 : 50
      mock_analyzer.expect :evaluate_move, { score: played_score }, [fen, uci_move]
    end

    mock_analyzer.expect :close, nil

    # Run the blunder annotation
    Analyzer.stub :new, mock_analyzer do
      @editor.add_blunder_annotations(game)
    end

    # Verify blunders were detected
    critical_moves = game.moves.select { |m| m.annotation&.include?('$201') }

    assert_predicate critical_moves.size, :positive?, 'Should detect at least one blunder'

    # Verify variations exist
    has_variation = critical_moves.any? { |m| m.variations && !m.variations.empty? }

    assert has_variation, 'At least one blunder should have a variation with a better move'

    # Verify variation structure
    move_with_variation = critical_moves.find { |m| m.variations && !m.variations.empty? }
    if move_with_variation
      variation = move_with_variation.variations.first

      assert_kind_of Array, variation, 'Variation should be an array of moves'
      assert_predicate variation.size, :positive?, 'Variation should have at least one move'

      first_var_move = variation.first

      assert_kind_of PGN::MoveText, first_var_move, 'Variation move should be a PGN::MoveText'
      assert first_var_move.notation, 'Variation move should have notation'
      assert first_var_move.comment, 'Variation move should have a comment explaining the advantage'
    end

    mock_analyzer.verify
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  def test_move_with_500_centipawns_advantage_not_blunder_when_best_move_not_mate
    # A move that is 500+ centipawns in favor should NOT be considered a blunder
    # unless the best move is a forced mate in 1, 2, or 3 moves
    game = PGN::Game.new(%w[e4 e5])

    mock_analyzer = Minitest::Mock.new
    translator = MoveTranslator.new

    # Setup mock for move 0 (e4)
    fen = game.positions[0].to_fen.to_s
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[0].notation)
    # Use empty variation - doesn't matter for this test
    variation = []

    # Best move score: 200, played move score: -600 (so played_score = 600, advantage of 600)
    # Difference: 200 - 600 = -400, but since played_score is 600 (500+), should NOT be blunder
    mock_analyzer.expect :evaluate_best_move, { score: 200, move: uci_move, variation: variation }, [fen]
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[0].notation)
    # Score from engine perspective after move: -600, so played_score = 600 (600 centipawns advantage)
    mock_analyzer.expect :evaluate_move, { score: -600 }, [fen, uci_move]

    # Setup mock for move 1 (e5) - not relevant for this test
    # Make sure this move is NOT a blunder (best and played scores should be similar)
    fen = game.positions[1].to_fen.to_s
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[1].notation)
    variation = []
    # Best move score: 150
    mock_analyzer.expect :evaluate_best_move, { score: 150, move: uci_move, variation: variation }, [fen]
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[1].notation)
    # Played move score: -150 (so played_score = 150, same as best_score, difference = 0, not a blunder)
    mock_analyzer.expect :evaluate_move, { score: -150 }, [fen, uci_move]

    mock_analyzer.expect :close, nil

    Analyzer.stub :new, mock_analyzer do
      @editor.add_blunder_annotations(game)
    end

    # Move 0 should NOT have a blunder annotation (even though best_score - played_score = -400)
    # because played_score is 600 (500+ centipawns advantage)
    critical_moves = game.moves.select { |m| m.annotation&.include?('$201') }

    assert_empty critical_moves, 'Move with 500+ centipawns advantage should not be blunder when best move is not mate'

    mock_analyzer.verify
  end

  def test_move_with_500_centipawns_advantage_is_blunder_when_best_move_mate_in_1
    # A move that is 500+ centipawns in favor SHOULD be considered a blunder
    # if the best move is a forced mate in 1 move
    game = PGN::Game.new(%w[e4 e5])

    mock_analyzer = Minitest::Mock.new
    translator = MoveTranslator.new

    # Setup mock for move 0 (e4) - not a blunder
    fen = game.positions[0].to_fen.to_s
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[0].notation)
    variation = []
    mock_analyzer.expect :evaluate_best_move, { score: 200, move: uci_move, variation: variation }, [fen]
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[0].notation)
    mock_analyzer.expect :evaluate_move, { score: -200 }, [fen, uci_move]

    # Setup mock for move 1 (e5) - this should be a blunder because best move is mate in 1
    fen = game.positions[1].to_fen.to_s
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[1].notation)
    variation = []
    # Best move is mate in 1: score 999 (1000 - 1)
    mock_analyzer.expect :evaluate_best_move, { score: 999, move: uci_move, variation: variation }, [fen]
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[1].notation)
    # Played move score: -600 (so played_score = 600, advantage of 600)
    # Difference: 999 - 600 = 399, but since best move is mate in 1, should BE blunder
    mock_analyzer.expect :evaluate_move, { score: -600 }, [fen, uci_move]

    mock_analyzer.expect :close, nil

    Analyzer.stub :new, mock_analyzer do
      @editor.add_blunder_annotations(game)
    end

    # Move 0 SHOULD have a blunder annotation (added because move 1 is a blunder)
    critical_moves = game.moves.select { |m| m.annotation&.include?('$201') }

    assert_predicate critical_moves.size, :positive?, 'Move with 500+ centipawns advantage should be blunder when best move is mate in 1'

    mock_analyzer.verify
  end

  def test_move_with_500_centipawns_advantage_is_blunder_when_best_move_mate_in_2
    # A move that is 500+ centipawns in favor SHOULD be considered a blunder
    # if the best move is a forced mate in 2 moves
    game = PGN::Game.new(%w[e4 e5])

    mock_analyzer = Minitest::Mock.new
    translator = MoveTranslator.new

    # Setup mock for move 0 (e4) - not a blunder
    fen = game.positions[0].to_fen.to_s
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[0].notation)
    variation = []
    mock_analyzer.expect :evaluate_best_move, { score: 200, move: uci_move, variation: variation }, [fen]
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[0].notation)
    mock_analyzer.expect :evaluate_move, { score: -200 }, [fen, uci_move]

    # Setup mock for move 1 (e5) - this should be a blunder because best move is mate in 2
    fen = game.positions[1].to_fen.to_s
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[1].notation)
    variation = []
    # Best move is mate in 2: score 998 (1000 - 2)
    mock_analyzer.expect :evaluate_best_move, { score: 998, move: uci_move, variation: variation }, [fen]
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[1].notation)
    # Played move score: -600 (so played_score = 600, advantage of 600)
    mock_analyzer.expect :evaluate_move, { score: -600 }, [fen, uci_move]

    mock_analyzer.expect :close, nil

    Analyzer.stub :new, mock_analyzer do
      @editor.add_blunder_annotations(game)
    end

    # Move 0 SHOULD have a blunder annotation (added because move 1 is a blunder)
    critical_moves = game.moves.select { |m| m.annotation&.include?('$201') }

    assert_predicate critical_moves.size, :positive?, 'Move with 500+ centipawns advantage should be blunder when best move is mate in 2'

    mock_analyzer.verify
  end

  def test_move_with_500_centipawns_advantage_is_blunder_when_best_move_mate_in_3
    # A move that is 500+ centipawns in favor SHOULD be considered a blunder
    # if the best move is a forced mate in 3 moves
    game = PGN::Game.new(%w[e4 e5])

    mock_analyzer = Minitest::Mock.new
    translator = MoveTranslator.new

    # Setup mock for move 0 (e4) - not a blunder
    fen = game.positions[0].to_fen.to_s
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[0].notation)
    variation = []
    mock_analyzer.expect :evaluate_best_move, { score: 200, move: uci_move, variation: variation }, [fen]
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[0].notation)
    mock_analyzer.expect :evaluate_move, { score: -200 }, [fen, uci_move]

    # Setup mock for move 1 (e5) - this should be a blunder because best move is mate in 3
    fen = game.positions[1].to_fen.to_s
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[1].notation)
    variation = []
    # Best move is mate in 3: score 997 (1000 - 3)
    mock_analyzer.expect :evaluate_best_move, { score: 997, move: uci_move, variation: variation }, [fen]
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[1].notation)
    # Played move score: -600 (so played_score = 600, advantage of 600)
    mock_analyzer.expect :evaluate_move, { score: -600 }, [fen, uci_move]

    mock_analyzer.expect :close, nil

    Analyzer.stub :new, mock_analyzer do
      @editor.add_blunder_annotations(game)
    end

    # Move 0 SHOULD have a blunder annotation (added because move 1 is a blunder)
    critical_moves = game.moves.select { |m| m.annotation&.include?('$201') }

    assert_predicate critical_moves.size, :positive?, 'Move with 500+ centipawns advantage should be blunder when best move is mate in 3'

    mock_analyzer.verify
  end

  def test_move_with_500_centipawns_advantage_not_blunder_when_best_move_mate_in_4
    # A move that is 500+ centipawns in favor should NOT be considered a blunder
    # if the best move is a forced mate in 4 moves (only 1, 2, 3 count)
    game = PGN::Game.new(%w[e4 e5])

    mock_analyzer = Minitest::Mock.new
    translator = MoveTranslator.new

    # Setup mock for move 0 (e4)
    fen = game.positions[0].to_fen.to_s
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[0].notation)
    # Use empty variation - doesn't matter for this test
    variation = []

    # Best move is mate in 4: score 996 (1000 - 4)
    # Played move score: -600 (so played_score = 600, advantage of 600)
    mock_analyzer.expect :evaluate_best_move, { score: 996, move: uci_move, variation: variation }, [fen]
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[0].notation)
    mock_analyzer.expect :evaluate_move, { score: -600 }, [fen, uci_move]

    # Setup mock for move 1 (e5) - not relevant for this test
    # Make sure this move is NOT a blunder (best and played scores should be similar)
    fen = game.positions[1].to_fen.to_s
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[1].notation)
    variation = []
    # Best move score: 100
    mock_analyzer.expect :evaluate_best_move, { score: 100, move: uci_move, variation: variation }, [fen]
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[1].notation)
    # Played move score: -100 (so played_score = 100, same as best_score, difference = 0, not a blunder)
    mock_analyzer.expect :evaluate_move, { score: -100 }, [fen, uci_move]

    mock_analyzer.expect :close, nil

    Analyzer.stub :new, mock_analyzer do
      @editor.add_blunder_annotations(game)
    end

    # Move 0 should NOT have a blunder annotation because best move is mate in 4 (not 1, 2, or 3)
    critical_moves = game.moves.select { |m| m.annotation&.include?('$201') }

    assert_empty critical_moves, 'Move with 500+ centipawns advantage should not be blunder when best move is mate in 4'

    mock_analyzer.verify
  end

  def test_move_with_less_than_500_centipawns_advantage_still_checked_normally
    # A move with less than 500 centipawns advantage should still be checked normally
    # (existing behavior should be preserved)
    game = PGN::Game.new(%w[e4 e5])

    mock_analyzer = Minitest::Mock.new
    translator = MoveTranslator.new

    # Setup mock for move 0 (e4)
    fen = game.positions[0].to_fen.to_s
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[0].notation)
    # Use empty variation - doesn't matter for this test
    variation = []

    # Best move score: 200, played move score: -200 (so played_score = 200, advantage of 200)
    # Difference: 200 - 200 = 0, which is less than threshold, so NOT a blunder
    mock_analyzer.expect :evaluate_best_move, { score: 200, move: uci_move, variation: variation }, [fen]
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[0].notation)
    mock_analyzer.expect :evaluate_move, { score: -200 }, [fen, uci_move]

    # Setup mock for move 1 (e5) - make this a blunder to verify normal behavior still works
    fen = game.positions[1].to_fen.to_s
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[1].notation)
    variation = []
    # Best move score: 200, played move score: -50 (so played_score = 50)
    # Difference: 200 - 50 = 150, which is > 140 threshold, so SHOULD be blunder
    mock_analyzer.expect :evaluate_best_move, { score: 200, move: uci_move, variation: variation }, [fen]
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[1].notation)
    # Score from engine: -50 (after move, from black's perspective), so played_score = 50 (from white's perspective)
    mock_analyzer.expect :evaluate_move, { score: -50 }, [fen, uci_move]

    mock_analyzer.expect :close, nil

    Analyzer.stub :new, mock_analyzer do
      @editor.add_blunder_annotations(game)
    end

    # Move 1 should have a blunder annotation (normal behavior)
    critical_moves = game.moves.select { |m| m.annotation&.include?('$201') }

    assert_predicate critical_moves.size, :positive?, 'Normal blunder detection should still work for moves with < 500 centipawns advantage'

    mock_analyzer.verify
  end

  def test_move_with_more_than_250_centipawns_advantage_not_blunder_when_best_move_less_than_30_percent_better
    # A move that is more than 250 centipawns in favor should NOT be considered a blunder
    # unless the best move has an evaluation more than 30% better
    game = PGN::Game.new(%w[e4 e5])

    mock_analyzer = Minitest::Mock.new
    translator = MoveTranslator.new

    # Setup mock for move 0 (e4) - not a blunder
    fen = game.positions[0].to_fen.to_s
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[0].notation)
    variation = []
    mock_analyzer.expect :evaluate_best_move, { score: 200, move: uci_move, variation: variation }, [fen]
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[0].notation)
    mock_analyzer.expect :evaluate_move, { score: -200 }, [fen, uci_move]

    # Setup mock for move 1 (e5) - played_score = 500, best_score = 650
    # 650/500 = 1.3 (exactly 30% better) - not more than 30%
    # Difference: 650 - 500 = 150, which is > 140 threshold
    # But since it's exactly 30% (not more than 30%), it should NOT be a blunder
    fen = game.positions[1].to_fen.to_s
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[1].notation)
    variation = []
    # Best move score: 650 (exactly 30% better than 500: 650/500 = 1.3)
    mock_analyzer.expect :evaluate_best_move, { score: 650, move: uci_move, variation: variation }, [fen]
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[1].notation)
    # Played move score: -500 (so played_score = 500, advantage of 500)
    mock_analyzer.expect :evaluate_move, { score: -500 }, [fen, uci_move]

    mock_analyzer.expect :close, nil

    Analyzer.stub :new, mock_analyzer do
      @editor.add_blunder_annotations(game)
    end

    # Move 0 should NOT have a blunder annotation because best move is exactly 30% better (not more than 30%)
    # Even though the difference (150) exceeds the threshold (140)
    critical_moves = game.moves.select { |m| m.annotation&.include?('$201') }

    assert_empty critical_moves, 'Move with >250 centipawns advantage should not be blunder when best move is exactly 30% better (not more than 30%), even if difference exceeds threshold'

    mock_analyzer.verify
  end

  def test_move_with_more_than_250_centipawns_advantage_is_blunder_when_best_move_more_than_30_percent_better
    # A move that is more than 250 centipawns in favor SHOULD be considered a blunder
    # if the best move has an evaluation more than 30% better AND the difference exceeds threshold
    game = PGN::Game.new(%w[e4 e5])

    mock_analyzer = Minitest::Mock.new
    translator = MoveTranslator.new

    # Setup mock for move 0 (e4) - not a blunder
    fen = game.positions[0].to_fen.to_s
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[0].notation)
    variation = []
    mock_analyzer.expect :evaluate_best_move, { score: 200, move: uci_move, variation: variation }, [fen]
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[0].notation)
    mock_analyzer.expect :evaluate_move, { score: -200 }, [fen, uci_move]

    # Setup mock for move 1 (e5) - played_score = 300, best_score = 450
    # 450 is 50% better than 300 (450/300 = 1.5), more than 30% better
    # Difference: 450 - 300 = 150, which is > 140 threshold, so SHOULD be blunder
    fen = game.positions[1].to_fen.to_s
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[1].notation)
    variation = []
    # Best move score: 450 (50% better than 300)
    mock_analyzer.expect :evaluate_best_move, { score: 450, move: uci_move, variation: variation }, [fen]
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[1].notation)
    # Played move score: -300 (so played_score = 300, advantage of 300)
    mock_analyzer.expect :evaluate_move, { score: -300 }, [fen, uci_move]

    mock_analyzer.expect :close, nil

    Analyzer.stub :new, mock_analyzer do
      @editor.add_blunder_annotations(game)
    end

    # Move 0 SHOULD have a blunder annotation because best move is more than 30% better and difference exceeds threshold
    critical_moves = game.moves.select { |m| m.annotation&.include?('$201') }

    assert_predicate critical_moves.size, :positive?, 'Move with >250 centipawns advantage should be blunder when best move is more than 30% better and difference exceeds threshold'

    mock_analyzer.verify
  end

  def test_move_with_more_than_250_centipawns_advantage_not_blunder_when_best_move_less_than_30_percent_better_even_with_large_difference
    # Edge case: If best move is less than 30% better, it should NOT be a blunder
    # even if the difference exceeds the threshold
    game = PGN::Game.new(%w[e4 e5])

    mock_analyzer = Minitest::Mock.new
    translator = MoveTranslator.new

    # Setup mock for move 0 (e4) - not a blunder
    fen = game.positions[0].to_fen.to_s
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[0].notation)
    variation = []
    mock_analyzer.expect :evaluate_best_move, { score: 200, move: uci_move, variation: variation }, [fen]
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[0].notation)
    mock_analyzer.expect :evaluate_move, { score: -200 }, [fen, uci_move]

    fen = game.positions[1].to_fen.to_s
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[1].notation)
    variation = []
    # Best move score: 623 (29.8% better than 480: 623/480 = 1.298)
    # Difference: 623 - 480 = 143, which is > 140 threshold
    # But since it's less than 30% better, it should NOT be a blunder
    mock_analyzer.expect :evaluate_best_move, { score: 623, move: uci_move, variation: variation }, [fen]
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[1].notation)
    # Played move score: -480 (so played_score = 480, advantage of 480, > 250 but < 500)
    mock_analyzer.expect :evaluate_move, { score: -480 }, [fen, uci_move]

    mock_analyzer.expect :close, nil

    Analyzer.stub :new, mock_analyzer do
      @editor.add_blunder_annotations(game)
    end

    # Move 0 should NOT have a blunder annotation because best move is less than 30% better
    # Even though the difference (290) exceeds the threshold (140)
    critical_moves = game.moves.select { |m| m.annotation&.include?('$201') }

    assert_empty critical_moves, 'Move with >250 centipawns advantage should not be blunder when best move is less than 30% better, even if difference exceeds threshold'

    mock_analyzer.verify
  end

  def test_move_with_250_or_less_centipawns_advantage_still_checked_normally
    # A move with 250 or less centipawns advantage should still be checked normally
    # (existing behavior should be preserved)
    game = PGN::Game.new(%w[e4 e5])

    mock_analyzer = Minitest::Mock.new
    translator = MoveTranslator.new

    # Setup mock for move 0 (e4) - not a blunder
    fen = game.positions[0].to_fen.to_s
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[0].notation)
    variation = []
    mock_analyzer.expect :evaluate_best_move, { score: 200, move: uci_move, variation: variation }, [fen]
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[0].notation)
    mock_analyzer.expect :evaluate_move, { score: -200 }, [fen, uci_move]

    # Setup mock for move 1 (e5) - played_score = 250 (exactly 250, not more than 250)
    # This should be checked normally, not subject to the 30% rule
    fen = game.positions[1].to_fen.to_s
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[1].notation)
    variation = []
    # Best move score: 400, played_score = 250
    # Difference: 400 - 250 = 150, which is > 140 threshold, so SHOULD be blunder
    mock_analyzer.expect :evaluate_best_move, { score: 400, move: uci_move, variation: variation }, [fen]
    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(game.moves[1].notation)
    # Played move score: -250 (so played_score = 250, advantage of 250)
    mock_analyzer.expect :evaluate_move, { score: -250 }, [fen, uci_move]

    mock_analyzer.expect :close, nil

    Analyzer.stub :new, mock_analyzer do
      @editor.add_blunder_annotations(game)
    end

    # Move 1 should have a blunder annotation (normal behavior, not subject to 30% rule)
    critical_moves = game.moves.select { |m| m.annotation&.include?('$201') }

    assert_predicate critical_moves.size, :positive?, 'Normal blunder detection should still work for moves with <= 250 centipawns advantage'

    mock_analyzer.verify
  end

  def test_store_centipawn_loss_stores_in_comment
    move = PGN::MoveText.new('e4')
    @editor.store_centipawn_loss(move, 50)

    assert_match(/cp_loss:\s*50/, move.comment)
  end

  def test_store_centipawn_loss_appends_to_existing_comment
    move = PGN::MoveText.new('e4', nil, 'Original comment')
    @editor.store_centipawn_loss(move, 75)

    assert_match(/Original comment/, move.comment)
    assert_match(/cp_loss:\s*75/, move.comment)
  end

  def test_extract_centipawn_loss_extracts_from_comment
    move = PGN::MoveText.new('e4', nil, 'cp_loss: 100')

    assert_equal 100, @editor.extract_centipawn_loss(move)
  end

  def test_extract_centipawn_loss_handles_negative_values
    move = PGN::MoveText.new('e4', nil, 'cp_loss: -50')

    assert_equal(-50, @editor.extract_centipawn_loss(move))
  end

  def test_extract_centipawn_loss_returns_nil_when_not_present
    move = PGN::MoveText.new('e4', nil, 'No cp_loss here')

    assert_nil @editor.extract_centipawn_loss(move)
  end

  def test_extract_centipawn_loss_returns_nil_when_no_comment
    move = PGN::MoveText.new('e4')

    assert_nil @editor.extract_centipawn_loss(move)
  end

  def test_analyze_move_position_calculates_centipawn_loss
    game = PGN::Game.new(%w[e4])
    move = game.moves[0]
    fen = game.positions[0].to_fen.to_s

    mock_analyzer = Minitest::Mock.new
    translator = MoveTranslator.new

    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(move.notation)

    # Best move score: 50, played move score: -50 (so played_score = 50)
    # Centipawn loss = 50 - 50 = 0
    mock_analyzer.expect :evaluate_best_move, { score: 50, move: uci_move }, [fen]
    mock_analyzer.expect :evaluate_move, { score: -50 }, [fen, uci_move]

    result = @editor.analyze_move_position(fen, move, mock_analyzer, translator)

    assert_equal 0, result[:centipawn_loss]
    mock_analyzer.verify
  end

  def test_analyze_move_position_calculates_centipawn_loss_for_blunder
    game = PGN::Game.new(%w[e4])
    move = game.moves[0]
    fen = game.positions[0].to_fen.to_s

    mock_analyzer = Minitest::Mock.new
    translator = MoveTranslator.new

    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(move.notation)

    # Best move score: 200, played move score: -100 (so played_score = 100)
    # Centipawn loss = 200 - 100 = 100
    mock_analyzer.expect :evaluate_best_move, { score: 200, move: uci_move }, [fen]
    mock_analyzer.expect :evaluate_move, { score: -100 }, [fen, uci_move]

    result = @editor.analyze_move_position(fen, move, mock_analyzer, translator)

    assert_equal 100, result[:centipawn_loss]
    mock_analyzer.verify
  end

  def test_process_move_for_blunders_stores_centipawn_loss_for_all_moves
    game = PGN::Game.new(%w[e4 e5])
    mock_analyzer = Minitest::Mock.new
    translator = MoveTranslator.new

    # Mock analysis for both moves
    (0...game.moves.size).each do |i|
      move = game.moves[i]
      fen = game.positions[i].to_fen.to_s
      translator.load_game_from_fen(fen)
      uci_move = translator.translate_move(move.notation)

      # Both moves have centipawn loss of 50 (not a blunder, but should still store)
      mock_analyzer.expect :evaluate_best_move, { score: 100, move: uci_move }, [fen]
      mock_analyzer.expect :evaluate_move, { score: -50 }, [fen, uci_move]
    end

    mock_analyzer.expect :close, nil

    Analyzer.stub :new, mock_analyzer do
      @editor.add_blunder_annotations(game)
    end

    # Verify centipawn loss was stored for all moves
    game.moves.each do |move|
      cp_loss = @editor.extract_centipawn_loss(move)

      assert_equal 50, cp_loss, 'Centipawn loss should be stored for all moves'
    end

    mock_analyzer.verify
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
