# frozen_string_literal: true

require_relative 'move_translator'
require_relative 'analyzer'
require_relative 'blunder_detector'
require_relative 'variation_builder'
require_relative 'annotation_shifter'

class GameEditor
  def initialize
    @blunder_detector = BlunderDetector.new
    @variation_builder = VariationBuilder.new
    @annotation_shifter = AnnotationShifter.new
  end

  def add_blunder_annotations(game)
    analyzer = Analyzer.new
    translator = MoveTranslator.new
    begin
      (0...game.moves.size).each do |i|
        process_move_for_blunders(game, i, analyzer, translator)
      end
    ensure
      analyzer&.close
    end
  end

  def process_move_for_blunders(game, move_index, analyzer, translator)
    move = game.moves[move_index]
    position = game.positions[move_index]
    fen = position.to_fen.to_s

    analysis_data = analyze_move_position(fen, move, analyzer, translator)
    return unless analysis_data

    return unless @blunder_detector.blunder_detected?(analysis_data[:best_score], analysis_data[:played_score])

    # Store centipawn loss only for blunders (moves that get $201 annotation)
    store_centipawn_loss(move, analysis_data[:centipawn_loss])

    annotate_critical_moment(game, move_index)
    @variation_builder.add_best_move_variation(move, fen, analysis_data)
  end

  def store_centipawn_loss(move, centipawn_loss)
    # Store centipawn loss in a comment in parseable format
    # Format: "cp_loss: 50" (PGN library will strip curly braces)
    cp_loss_comment = "cp_loss: #{centipawn_loss}"

    move.comment = if move.comment && !move.comment.empty?
                     # Append to existing comment, separated by space
                     "#{move.comment} #{cp_loss_comment}"
                   else
                     cp_loss_comment
                   end
  end

  def extract_centipawn_loss(move)
    # Extract centipawn loss from move comment
    # Format: "cp_loss: 50" (PGN library strips curly braces)
    return nil unless move.comment

    # Try both formats: with braces (if manually set) and without (PGN library format)
    match = move.comment.match(/\{?cp_loss:\s*(-?\d+)\}?/)
    return nil unless match

    match[1].to_i
  end

  def analyze_move_position(fen, move, analyzer, translator)
    best_move_analysis = analyzer.evaluate_best_move(fen)
    return nil unless best_move_analysis&.[](:score)

    translator.load_game_from_fen(fen)
    uci_move = translator.translate_move(move.notation)
    played_move_analysis = analyzer.evaluate_move(fen, uci_move)
    return nil unless played_move_analysis&.[](:score)

    best_score = best_move_analysis[:score]
    # The score from evaluate_move is from the perspective of the side whose turn it is
    # AFTER the move has been made. We want the score from the perspective of the player
    # who MADE the move, so we negate it.
    played_score = -played_move_analysis[:score]

    # Centipawn loss: difference between best move and played move
    # Both scores are from the perspective of the player who is about to move (before the move)
    centipawn_loss = best_score - played_score

    {
      best_score: best_score,
      played_score: played_score,
      centipawn_loss: centipawn_loss,
      best_move_analysis: best_move_analysis
    }
  end

  def annotate_critical_moment(game, move_index)
    # Add the $201 annotation to the PREVIOUS move to mark the critical moment
    # (PGN convention: $201 indicates a critical position where the next player can err)
    @annotation_shifter.add_201_to_move(game.moves[move_index - 1]) if move_index.positive?
  end

  # Modifies a PGN::Game object in place.
  # If a $201 annotation (critical moment) is found on move M,
  # it is moved to move M+1, as semantically $201 applies to the *next* move.
  # The PGN parser might associate it with M. This method corrects that.
  def shift_critical_annotations(game)
    @annotation_shifter.shift_critical_annotations(game)
  end

  # Reverses shift_critical_annotations - moves $201 from move M+1 back to move M.
  # This is used when saving games that were analyzed by our system, where
  # add_blunder_annotations places $201 on move i-1 (before the blunder),
  # which is the correct placement for PGN files.
  def unshift_critical_annotations(game)
    @annotation_shifter.unshift_critical_annotations(game)
  end
end
