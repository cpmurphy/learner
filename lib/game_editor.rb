# frozen_string_literal: true
#
require_relative 'move_translator'
require_relative 'analyzer'
require_relative 'uci_to_san_converter'

class GameEditor
  BLUNDER_THRESHOLD = 140 # In centipawns. A drop of 1.4 pawn value is a blunder.

  def initialize
    @translator = MoveTranslator.new
    @uci_converter = UciToSanConverter.new
  end

  def add_blunder_annotations(game)
    analyzer = Analyzer.new
    begin
      (0...game.moves.size).each do |i|
        move = game.moves[i]
        position = game.positions[i]
        fen = position.to_fen.to_s

        best_move_analysis = analyzer.evaluate_best_move(fen)
        next unless best_move_analysis&.[](:score)

        uci_move = @translator.translate_move(move.notation)
        played_move_analysis = analyzer.evaluate_move(fen, uci_move)
        next unless played_move_analysis&.[](:score)

        best_score = best_move_analysis[:score]
        played_score = played_move_analysis[:score]

        is_blunder = false
        if position.player == :white # White to move
          # A blunder for White means the evaluation drops significantly.
          is_blunder = (best_score - played_score) > BLUNDER_THRESHOLD
        else # Black to move
          # A blunder for Black means the evaluation rises significantly (for White).
          is_blunder = (played_score - best_score) > BLUNDER_THRESHOLD
        end

        next unless is_blunder

        # Add the $201 annotation
        add_201_to_move(move)

        # Add variation with the best move
        best_move_uci = best_move_analysis[:move]
        if best_move_uci
          best_move_san = @uci_converter.convert(fen, best_move_uci)

          # Create a variation with the best move
          variation_move = PGN::MoveText.new(best_move_san)

          # Add a comment explaining the score difference
          score_diff = (best_score - played_score).abs
          variation_move.comment = "Better move (advantage: #{format_centipawns(score_diff)})"

          # Add the variation to the move
          move.variations ||= []
          move.variations << [variation_move]
        end
      end
    ensure
      analyzer&.close
    end
  end

  # Format centipawns as a human-readable advantage string
  # @param centipawns [Integer] the advantage in centipawns
  # @return [String] formatted advantage (e.g., "+1.4" or "+M5" for mate in 5)
  def format_centipawns(centipawns)
    if centipawns > 900
      # This is likely a mate score
      mate_in = (1000 - centipawns).abs
      "+M#{mate_in}"
    else
      pawns = centipawns / 100.0
      format('+%.1f', pawns)
    end
  end

  # Modifies a PGN::Game object in place.
  # If a $201 annotation (critical moment) is found on move M,
  # it is moved to move M+1, as semantically $201 applies to the *next* move.
  # The PGN parser might associate it with M. This method corrects that.
  def shift_critical_annotations(game)
    moves = game.moves
    i = moves.size - 1
    while i.positive?
      current_move = moves[i]
      prev_move = moves[i - 1]

      if prev_move.respond_to?(:annotation) && prev_move.annotation&.include?('$201')
        # Only shift annotation to a real move, not MoveText.
        if current_move.respond_to?(:annotation)
          remove_201_from_move(prev_move)

          add_201_to_move(current_move)
        end
      end
      i -= 1
    end
  end

  def remove_201_from_move(move)
    move.annotation.delete('$201')
    move.annotation = nil if move.annotation.empty?
  end

  def add_201_to_move(move)
    move.annotation ||= [] # Initialize if nil
    move.annotation << '$201' unless move.annotation.include?('$201')
  end
end
