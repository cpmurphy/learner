# frozen_string_literal: true

require_relative 'input_validator'

module StockfishPool
  # Parses UCI "info"/"bestmove" output into plain data. Scores are reported as
  # the engine gives them: from the perspective of the side to move.
  module InfoParser
    SCORE_TYPES = { 'cp' => :cp, 'mate' => :mate }.freeze

    module_function

    # @return [Hash] { bestmove: String or nil, lines: [{ multipv:, move:, score:, depth:, pv: }] }
    def parse(output_lines)
      by_multipv = {}
      bestmove = nil
      output_lines.each do |line|
        if line.start_with?('bestmove ')
          bestmove = parse_bestmove(line)
        elsif line.start_with?('info ')
          info = parse_info(line)
          by_multipv[info[:multipv]] = info if info
        end
      end
      { bestmove: bestmove, lines: by_multipv.sort.map(&:last) }
    end

    def parse_bestmove(line)
      move = line.split[1]
      InputValidator.valid_uci_move?(move) ? move : nil
    end

    def parse_info(line)
      tokens = line.split
      score = parse_score(tokens)
      return nil unless score

      pv = moves_after(tokens, 'pv')
      {
        multipv: integer_after(tokens, 'multipv') || 1,
        move: pv.first,
        score: score,
        depth: integer_after(tokens, 'depth') || 0,
        pv: pv
      }
    end

    # Bound scores (lowerbound/upperbound) come from aspiration windows and are
    # not final, so they are skipped.
    def parse_score(tokens)
      index = tokens.index('score')
      return nil unless index

      type = SCORE_TYPES[tokens[index + 1]]
      value = Integer(tokens[index + 2].to_s, 10, exception: false)
      return nil unless type && value
      return nil if %w[lowerbound upperbound].include?(tokens[index + 3])

      { type => value }
    end

    def integer_after(tokens, key)
      index = tokens.index(key)
      index && Integer(tokens[index + 1].to_s, 10, exception: false)
    end

    def moves_after(tokens, key)
      index = tokens.index(key)
      return [] unless index

      tokens[(index + 1)..].take_while { |move| InputValidator.valid_uci_move?(move) }
    end
  end
end
