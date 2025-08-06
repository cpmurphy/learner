# frozen_string_literal: true

module GameEditor
  BLUNDER_THRESHOLD = 150 # In centipawns. A drop of 1.5 pawn value is a blunder.

  def self.add_blunder_annotations(game)
    analyzer = Analyzer.new
    begin
      (0...game.moves.size).each do |i|
        move = game.moves[i]
        # PGN::MoveText objects (like game results) can't be analyzed.
        next unless move.respond_to?(:from)
        position = game.positions[i]
        fen = position.to_fen.to_s

        best_move_analysis = analyzer.evaluate_best_move(fen)
        next unless best_move_analysis&.[](:score)

        uci_move = "#{move.from}#{move.to}#{move.promotion || ''}".downcase
        played_move_analysis = analyzer.evaluate_move(fen, uci_move)
        next unless played_move_analysis&.[](:score)

        best_score = best_move_analysis[:score]
        played_score = played_move_analysis[:score]

        is_blunder = false
        if position.turn == 'w' # White to move
          # A blunder for White means the evaluation drops significantly.
          is_blunder = (best_score - played_score) > BLUNDER_THRESHOLD
        else # Black to move
          # A blunder for Black means the evaluation rises significantly (for White).
          is_blunder = (played_score - best_score) > BLUNDER_THRESHOLD
        end

        add_201_to_move(move) if is_blunder
      end
    ensure
      analyzer&.close
    end
  end

  # Modifies a PGN::Game object in place.
  # If a $201 annotation (critical moment) is found on move M,
  # it is moved to move M+1, as semantically $201 applies to the *next* move.
  # The PGN parser might associate it with M. This method corrects that.
  def self.shift_critical_annotations(game)
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

  def self.remove_201_from_move(move)
    move.annotation.delete('$201')
    move.annotation = nil if move.annotation.empty?
  end

  def self.add_201_to_move(move)
    move.annotation ||= [] # Initialize if nil
    move.annotation << '$201' unless move.annotation.include?('$201')
  end
end
