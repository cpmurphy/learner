# frozen_string_literal: true

require_relative 'uci_to_san_converter'
require_relative 'move_translator'

class VariationBuilder
  def initialize
    @uci_converter = UciToSanConverter.new
  end

  # Adds a variation to the move showing the best continuation
  # @param move [PGN::MoveText] the move to add the variation to
  # @param fen [String] the FEN position before the move
  # @param analysis_data [Hash] analysis data including best move, scores
  def add_best_move_variation(move, fen, analysis_data)
    best_move_analysis = analysis_data[:best_move_analysis]
    best_move_uci = best_move_analysis[:move]
    return unless best_move_uci

    continuation_moves = best_move_analysis[:variation] || []
    full_variation = [best_move_uci] + continuation_moves

    # Build a variation with 12 ply (6 full moves) to show the continuation
    variation_sequence = build_variation_sequence(fen, full_variation, 12)
    return if variation_sequence.empty?

    add_variation_comment(variation_sequence, analysis_data[:best_score], analysis_data[:played_score])

    # Add the variation to the move
    move.variations ||= []
    move.variations << variation_sequence
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
      # Skip invalid moves
      next unless uci_move && uci_move != '--'

      begin
        # Convert UCI to SAN using the current position
        san_move = @uci_converter.convert(current_fen, uci_move)
        pgn_move = PGN::MoveText.new(san_move)
        sequence << PGN::MoveText.new(san_move) unless pgn_move.notation.nil?

        # Update the position by applying the move
        translator = MoveTranslator.new
        translator.load_game_from_fen(current_fen)
        translator.translate_move(san_move)
        current_fen = translator.board_as_fen
      rescue StandardError
        # If a move is invalid, stop building the variation
        # This can happen if the variation contains moves that aren't valid for the position
        break
      end
    end

    sequence
  end

  private

  # Adds a comment to the first move of the variation explaining the advantage
  # @param variation_sequence [Array<PGN::MoveText>] the variation sequence
  # @param best_score [Integer] the best move's score
  # @param played_score [Integer] the played move's score
  def add_variation_comment(variation_sequence, best_score, played_score)
    # Add a comment to the first move explaining the advantage
    score_diff = (best_score - played_score).abs
    variation_sequence[0].comment = "Better line (advantage: #{format_centipawns(score_diff)})"
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
end
