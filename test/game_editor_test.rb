# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/mock'
require 'pgn' # Gem for PGN parsing, used to construct test objects
require_relative '../lib/game_editor'
require_relative '../lib/move_translator'

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

      # Build variation from the continuation moves AFTER the best move
      # The variation should not include the best move itself
      translator.load_game_from_fen(fen)
      translator.translate_move(game.moves[i].notation) # Apply current move
      variation = ((i + 1)...(i + 3)).map do |j|
        break unless game.positions[j] && game.moves[j]

        translator.translate_move(game.moves[j].notation)
      end
      variation = [] if variation.nil? # Handle break returning nil

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

      # Mock variation to be continuation moves AFTER the best move
      translator.load_game_from_fen(fen)
      translator.translate_move(game.moves[i].notation) # Apply current move
      variation = ((i + 1)...(i + 3)).map do |j|
        break unless game.positions[j] && game.moves[j]

        translator.translate_move(game.moves[j].notation)
      end
      variation = [] if variation.nil? # Handle break returning nil

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

  def test_process_move_for_blunders_stores_centipawn_loss_only_for_blunders
    game = PGN::Game.new(%w[e4 e5])
    mock_analyzer = Minitest::Mock.new
    translator = MoveTranslator.new

    # Mock analysis for first move (e4) - not a blunder (centipawn loss < 140)
    move_1 = game.moves[0]
    fen_1 = game.positions[0].to_fen.to_s
    translator.load_game_from_fen(fen_1)
    uci_move_1 = translator.translate_move(move_1.notation)
    # Centipawn loss: 100 - 50 = 50 (not a blunder)
    mock_analyzer.expect :evaluate_best_move, { score: 100, move: uci_move_1 }, [fen_1]
    mock_analyzer.expect :evaluate_move, { score: -50 }, [fen_1, uci_move_1]

    # Mock analysis for second move (e5) - is a blunder (centipawn loss > 140)
    move_2 = game.moves[1]
    fen_2 = game.positions[1].to_fen.to_s
    translator.load_game_from_fen(fen_2)
    uci_move_2 = translator.translate_move(move_2.notation)
    # Centipawn loss: 200 - 50 = 150 (is a blunder)
    mock_analyzer.expect :evaluate_best_move, { score: 200, move: uci_move_2 }, [fen_2]
    mock_analyzer.expect :evaluate_move, { score: -50 }, [fen_2, uci_move_2]

    mock_analyzer.expect :close, nil

    Analyzer.stub :new, mock_analyzer do
      @editor.add_blunder_annotations(game)
    end

    # Verify centipawn loss was NOT stored for non-blunder move
    cp_loss_1 = @editor.extract_centipawn_loss(game.moves[0])

    assert_nil cp_loss_1, 'Centipawn loss should NOT be stored for non-blunder moves'

    # Verify centipawn loss WAS stored for blunder move
    cp_loss_2 = @editor.extract_centipawn_loss(game.moves[1])

    assert_equal 150, cp_loss_2, 'Centipawn loss should be stored for blunder moves'

    mock_analyzer.verify
  end
end
