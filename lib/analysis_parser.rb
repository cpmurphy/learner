# frozen_string_literal: true

require_relative 'stockfish_engine'
require 'timeout'

# A class to parse Stockfish analysis output
class AnalysisParser
  CENTIPAWN_PATTERN = /multipv (\d+) score cp (-?\d+) .* pv (\w+)((\s(\w+))*)/
  MATE_PATTERN = /multipv (\d+) score mate (-?\d+) .* pv (\w+)((\s(\w+))*)/
  IMMEDIATE_MATE_PATTERN = /info depth 0 score mate 0/
  IMMEDIATE_DRAW_PATTERN = /info depth 0 score cp 0/

  # Extract the top moves and their corresponding ponder moves
  #
  # rubocop:disable Layout/LineLength
  # analysis is a string like
  # "info depth 14 seldepth 22 multipv 1 score cp 166 nodes 110505 nps 2166764 hashfull 30 tbhits 0 time 51 pv h7h3 e6f7 h3h7 f7e6 e4d5 e6d5 d3e4 d5e4 h7f7 e7f6 f7b3 e4f5 e1f1 f5g4 b3d3 b7g2 h1g2 d8a8 g2g1 g4h3 d3e2
  # info depth 14 seldepth 29 multipv 2 score cp 135 nodes 110505 nps 2166764 hashfull 30 tbhits 0 time 51 pv e4d5 e6d5 d3e4 d5e4 h7f7 e7f6 f7b3 e4f5 e1f1 f5g4 b3d3 b7g2 h1g2 d8a8 g2g1 f6g5 d3e2 g4h4 e3f2 h4h3 f2e1 e8g8
  # info depth 14 seldepth 14 multipv 3 score cp 0 nodes 110505 nps 2166764 hashfull 30 tbhits 0 time 51 pv e1f1 d5f4 f1f4 e5f4 h7h3 e6e5 e3f4 e5f6 h3h4 f6e6 h4h3 e6f6
  # bestmove h6h3 ponder e6f7"
  # rubocop:enable Layout/LineLength
  def parse(analysis)
    analysis.split("\n").each_with_object([]) do |line, moves|
      next unless line.start_with?('info')

      parse_line(line, moves)
    end
  end

  private

  def parse_line(line, moves)
    return parse_centipawn_score(line, moves) if line.match?(CENTIPAWN_PATTERN)
    return parse_mate_score(line, moves) if line.match?(MATE_PATTERN)
    return moves << { score: -1000 } if line.match?(IMMEDIATE_MATE_PATTERN)

    moves << { score: 0 } if line.match?(IMMEDIATE_DRAW_PATTERN)
  end

  def parse_centipawn_score(line, moves)
    match = line.match(CENTIPAWN_PATTERN)
    index = match[1].to_i - 1
    moves[index] = {
      score: match[2].to_i,
      move: match[3]
    }
    add_variation(moves[index], match[4])
  end

  def parse_mate_score(line, moves)
    match = line.match(MATE_PATTERN)
    index = match[1].to_i - 1
    mate_score = match[2].to_i
    moves[index] = {
      score: calculate_mate_score(mate_score),
      move: match[3]
    }
    add_variation(moves[index], match[4])
  end

  def calculate_mate_score(mate_score)
    base = mate_score.negative? ? -1000 : 1000
    base - mate_score
  end

  def add_variation(move_data, variation_string)
    move_data[:variation] = variation_string.split.map(&:strip) if variation_string
  end
end
