# frozen_string_literal: true

require_relative 'chess_rules'
require_relative 'uci_to_san_converter'
require_relative 'move_translator'

class VariationBuilder
  def initialize
    @uci_converter = UciToSanConverter.new
  end

  # Plies a variation normally shows (6 full moves).
  VARIATION_PLIES = 12
  # A line that would stop in the middle of an exchange or a series of checks
  # is extended while its next move is a capture or a check, by at most this
  # many plies, so it never ends with a piece hanging that is obviously
  # recaptured, or with a check unanswered.
  MAX_CAPTURE_EXTENSION_PLIES = 8

  # Adds a variation to the move showing the best continuation
  # @param move [PGN::MoveText] the move to add the variation to
  # @param fen [String] the FEN position before the move
  # @param analysis_data [Hash] analysis data including best move, scores
  # @param continuation [#call, nil] given a FEN, returns the engine's best line
  #   there ({ move:, variation: }); used when the engine's line runs out right
  #   after a capture or a check. Without it the line ends where the engine's did.
  def add_best_move_variation(move, fen, analysis_data, continuation: nil)
    best_move_analysis = analysis_data[:best_move_analysis]
    best_move_uci = best_move_analysis[:move]
    return unless best_move_uci

    continuation_moves = best_move_analysis[:variation] || []
    full_variation = [best_move_uci] + continuation_moves

    variation_sequence = build_variation_sequence(fen, full_variation, VARIATION_PLIES, continuation: continuation)
    return if variation_sequence.empty?

    add_variation_comment(variation_sequence, analysis_data[:best_score], analysis_data[:played_score])

    # Add the variation to the move
    move.variations ||= []
    move.variations << variation_sequence
  end

  # Build a sequence of moves for a variation. After +max_moves+ plies it keeps
  # going while the next move is a capture, a check or the reply to one (up to
  # MAX_CAPTURE_EXTENSION_PLIES more). If the moves run out right after one,
  # +continuation+ (when given) is asked for the engine's line from there, and
  # its captures and checks are added the same way.
  # @param fen [String] the starting FEN position
  # @param uci_moves [Array<String>] array of UCI moves
  # @param max_moves [Integer] number of plies to include outside an exchange
  # @param continuation [#call, nil] see add_best_move_variation
  # @return [Array<PGN::MoveText>] array of move objects
  def build_variation_sequence(fen, uci_moves, max_moves, continuation: nil)
    limit = max_moves + MAX_CAPTURE_EXTENSION_PLIES
    sequence = []
    current_fen = append_moves(sequence, fen, uci_moves, max_moves, limit)
    return sequence unless continuation && current_fen && sequence.size < limit
    return sequence unless sequence.last && forcing?(sequence.last.notation.to_s, current_fen)
    # After mate or stalemate there is nothing left to show
    return sequence if ChessRules::Moves.legal_moves(ChessRules::Position.from_fen(current_fen)).empty?

    append_moves(sequence, current_fen, engine_line(continuation, current_fen), sequence.size, limit)
    sequence
  end

  private

  # Appends +uci_moves+ to +sequence+: every move while it is shorter than
  # +plies+, then only captures, checks and replies to checks until it
  # reaches +limit+.
  # @return [String, nil] the FEN after the last move added, or nil if the
  #   moves stopped early (an illegal move or a quiet move past +plies+)
  def append_moves(sequence, fen, uci_moves, plies, limit)
    # Null moves are skipped
    uci_moves.reject { |uci_move| uci_move.nil? || uci_move == '--' }.each do |uci_move|
      san_move, next_fen = next_move(sequence.size, fen, uci_move, plies, limit)
      return nil unless san_move

      sequence << PGN::MoveText.new(san_move)
      fen = next_fen
    end
    fen
  rescue StandardError
    nil
  end

  # The SAN of +uci_move+ and the FEN after it, if a sequence of +size+ plies
  # takes it; nil otherwise. An illegal move ends the variation, since the
  # engine's line may not fit the position.
  def next_move(size, fen, uci_move, plies, limit)
    san_move = size < limit && @uci_converter.convert(fen, uci_move)
    return nil unless san_move

    next_fen = fen_after(fen, san_move)
    [san_move, next_fen] if size < plies || in_exchange?(fen, san_move, next_fen)
  end

  def fen_after(fen, san_move)
    translator = MoveTranslator.new
    translator.load_game_from_fen(fen)
    translator.translate_move(san_move)
    translator.board_as_fen
  end

  # Whether the move +san_move+ from +fen+ (leading to +next_fen+) answers a
  # check, or is itself a capture or a check.
  def in_exchange?(fen, san_move, next_fen)
    in_check?(fen) || forcing?(san_move, next_fen)
  end

  # Whether the move whose SAN is +san_move+, leading to +fen_after+, is a
  # capture or a check: a line that stops right after one leaves the reply out.
  def forcing?(san_move, fen_after)
    san_move.include?('x') || in_check?(fen_after)
  end

  # Whether the side to move in +fen+ is in check.
  def in_check?(fen)
    position = ChessRules::Position.from_fen(fen)
    position.in_check?(position.side)
  end

  def engine_line(continuation, fen)
    line = continuation.call(fen)
    return [] unless line&.[](:move)

    [line[:move]] + (line[:variation] || [])
  end

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
