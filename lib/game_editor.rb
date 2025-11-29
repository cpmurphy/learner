# frozen_string_literal: true
#
require_relative 'move_translator'
require_relative 'analyzer'
require_relative 'uci_to_san_converter'

class GameEditor
  BLUNDER_THRESHOLD = 140 # In centipawns. A drop of 1.4 pawn value is a blunder.

  def initialize
    @uci_converter = UciToSanConverter.new
  end

  def add_blunder_annotations(game)
    analyzer = Analyzer.new
    translator = MoveTranslator.new
    begin
      (0...game.moves.size).each do |i|
        move = game.moves[i]
        position = game.positions[i]
        fen = position.to_fen.to_s

        best_move_analysis = analyzer.evaluate_best_move(fen)
        next unless best_move_analysis&.[](:score)

        translator.load_game_from_fen(fen)
        uci_move = translator.translate_move(move.notation)
        played_move_analysis = analyzer.evaluate_move(fen, uci_move)
        next unless played_move_analysis&.[](:score)

        best_score = best_move_analysis[:score]
        # The score from evaluate_move is from the perspective of the side whose turn it is
        # AFTER the move has been made. We want the score from the perspective of the player
        # who MADE the move, so we negate it.
        played_score = -played_move_analysis[:score]

        # Now both scores are from the perspective of the player who is about to move.
        # A blunder means the evaluation drops significantly (for both White and Black).
        is_blunder = (best_score - played_score) > BLUNDER_THRESHOLD

        next unless is_blunder

        # Add the $201 annotation to the PREVIOUS move to mark the critical moment
        # (PGN convention: $201 indicates a critical position where the next player can err)
        if i > 0
          add_201_to_move(game.moves[i - 1])
        end

        # Add variation with the best move and continuation
        best_move_uci = best_move_analysis[:move]
        continuation_moves = best_move_analysis[:variation] || []

        if best_move_uci
          # The variation includes the best move plus the continuation
          full_variation = [best_move_uci] + continuation_moves

          # Build a variation with 8 ply (4 full moves) to show the continuation
          variation_sequence = build_variation_sequence(fen, full_variation, 8)

          unless variation_sequence.empty?
            # Add a comment to the first move explaining the advantage
            score_diff = (best_score - played_score).abs
            variation_sequence[0].comment = "Better line (advantage: #{format_centipawns(score_diff)})"

            # Add the variation to the move
            move.variations ||= []
            move.variations << variation_sequence
          end
        end
      end
    ensure
      analyzer&.close
    end
  end

  # Build a sequence of moves for a variation
  # @param fen [String] the starting FEN position
  # @param uci_moves [Array<String>] array of UCI moves
  # @param max_moves [Integer] maximum number of moves to include
  # @return [Array<PGN::MoveText>] array of move objects
  def build_variation_sequence(fen, uci_moves, max_moves)
    sequence = []
    current_fen = fen

    uci_moves.take(max_moves).each do |uci_move|
      # Convert UCI to SAN using the current position
      begin
        san_move = @uci_converter.convert(current_fen, uci_move)
        sequence << PGN::MoveText.new(san_move)

        # Update the position by applying the move
        translator = MoveTranslator.new
        translator.load_game_from_fen(current_fen)
        translator.translate_move(san_move)
        current_fen = translator.board_as_fen
      rescue StandardError => e
        # If we can't convert or apply a move, stop the variation here
        puts "Warning: Failed to process variation move #{uci_move}: #{e.message}"
        break
      end
    end

    sequence
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

  # Reverses shift_critical_annotations - moves $201 from move M+1 back to move M.
  # This is used when saving games that were analyzed by our system, where
  # add_blunder_annotations places $201 on move i-1 (before the blunder),
  # which is the correct placement for PGN files.
  def unshift_critical_annotations(game)
    moves = game.moves
    return if moves.empty?

    # Start from the beginning and move $201 backwards
    (1...moves.size).each do |i|
      current_move = moves[i]
      prev_move = moves[i - 1]

      if current_move.respond_to?(:annotation) && current_move.annotation&.include?('$201')
        # Only unshift annotation if previous move is a real move
        if prev_move.respond_to?(:annotation)
          remove_201_from_move(current_move)

          add_201_to_move(prev_move)
        end
      end
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
