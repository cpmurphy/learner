# frozen_string_literal: true

require_relative 'input_validator'

module StockfishPool
  class InvalidRequest < StandardError; end

  # A validated, clamped search. Only values in this struct ever reach the engine.
  SearchRequest = Struct.new(:fen, :moves, :lane, :depth, :movetime_ms, :nodes, :multipv, :subject,
                             keyword_init: true) do
    def applied
      { depth: depth, movetime_ms: movetime_ms, nodes: nodes, multipv: multipv }
    end
  end

  # Turns untrusted request parameters into a SearchRequest. Search limits are
  # clamped to the lane's ceilings rather than rejected; malformed input is rejected.
  class RequestBuilder
    LANES = { 'interactive' => :interactive, 'batch' => :batch }.freeze

    def initialize(config)
      @config = config
    end

    def build(params)
      raise InvalidRequest, 'Request body must be a JSON object' unless params.is_a?(Hash)

      lane = parse_lane(params['lane'])
      limits = @config.lane(lane)
      SearchRequest.new(
        fen: parse_fen(params['fen']),
        moves: parse_moves(params['moves']),
        lane: lane,
        subject: parse_subject(params['subject']),
        **clamped_limits(params, limits)
      ).freeze
    end

    private

    def clamped_limits(params, limits)
      {
        depth: clamp(params, 'depth', limits.default_depth, limits.max_depth),
        movetime_ms: clamp(params, 'movetime_ms', limits.max_movetime_ms, limits.max_movetime_ms),
        nodes: clamp(params, 'nodes', limits.max_nodes, limits.max_nodes),
        multipv: clamp(params, 'multipv', 1, limits.max_multipv)
      }
    end

    def parse_lane(value)
      return :interactive if value.nil?

      LANES.fetch(value) { raise InvalidRequest, 'lane must be "interactive" or "batch"' }
    end

    def parse_fen(fen)
      raise InvalidRequest, 'Invalid FEN' unless InputValidator.valid_fen?(fen)

      fen.dup.freeze
    end

    def parse_moves(moves)
      return [].freeze if moves.nil?
      raise InvalidRequest, 'moves must be an array' unless moves.is_a?(Array)
      raise InvalidRequest, "At most #{@config.max_moves} moves are allowed" if moves.length > @config.max_moves
      raise InvalidRequest, 'Invalid UCI move' unless moves.all? { |move| InputValidator.valid_uci_move?(move) }

      moves.map { |move| move.dup.freeze }.freeze
    end

    def parse_subject(subject)
      return nil if subject.nil?
      raise InvalidRequest, 'Invalid subject' unless InputValidator.valid_subject?(subject)

      subject.dup.freeze
    end

    def clamp(params, key, default, max)
      value = params[key]
      return default if value.nil?
      raise InvalidRequest, "#{key} must be a positive integer" unless value.is_a?(Integer) && value.positive?

      [value, max].min
    end
  end
end
