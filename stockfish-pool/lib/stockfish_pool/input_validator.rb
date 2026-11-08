# frozen_string_literal: true

module StockfishPool
  # Validates untrusted chess input (FEN strings, UCI moves, subjects) before it
  # is used to build UCI commands. Every UCI command is a single line, so input
  # containing a line break could smuggle extra commands to the engine; these
  # checks accept only the exact shapes the engine needs.
  module InputValidator
    UCI_MOVE = /\A[a-h][1-8][a-h][1-8][qrbn]?\z/
    SUBJECT = /\A[A-Za-z0-9_-]{1,64}\z/
    RANK = /\A[pnbrqkPNBRQK1-8]{1,8}\z/
    # Side to move, castling rights, en passant square, halfmove clock, fullmove number.
    FIELD_PATTERNS = [
      /\A[wb]\z/,
      /\A(?:-|(?=.)K?Q?k?q?)\z/,
      /\A(?:-|[a-h][36])\z/,
      /\A\d{1,4}\z/,
      /\A\d{1,4}\z/
    ].freeze
    MAX_FEN_LENGTH = 100

    module_function

    def valid_uci_move?(move)
      move.is_a?(String) && UCI_MOVE.match?(move)
    end

    def valid_subject?(subject)
      subject.is_a?(String) && SUBJECT.match?(subject)
    end

    def valid_fen?(fen)
      return false unless fen.is_a?(String) && fen.length <= MAX_FEN_LENGTH

      fields = fen.split(' ', -1)
      return false unless fields.length == 6

      placement, *rest = fields
      valid_placement?(placement) && FIELD_PATTERNS.zip(rest).all? { |pattern, field| pattern.match?(field) }
    end

    def valid_placement?(placement)
      ranks = placement.split('/', -1)
      return false unless ranks.length == 8
      return false unless ranks.all? { |rank| RANK.match?(rank) && rank_width(rank) == 8 }

      placement.count('K') == 1 && placement.count('k') == 1
    end

    def rank_width(rank)
      rank.chars.sum { |char| char.match?(/\d/) ? char.to_i : 1 }
    end
  end
end
