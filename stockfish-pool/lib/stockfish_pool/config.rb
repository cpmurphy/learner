# frozen_string_literal: true

module StockfishPool
  # Service configuration, read from environment variables with safe defaults
  # sized for a small shared VPS. Every limit is a hard ceiling: callers can ask
  # for less, never for more.
  class Config
    LaneLimits = Struct.new(
      :default_depth, :max_depth, :max_movetime_ms, :max_nodes, :max_multipv, :queue_max, :queue_wait_s,
      keyword_init: true
    )

    MIN_TOKEN_LENGTH = 24

    attr_reader :engine_command, :pool_size, :reserved_interactive, :threads, :hash_mb, :lanes,
                :global_engine_sec_per_min, :subject_engine_sec_per_min, :subject_burst_sec,
                :subject_batch_engine_sec_per_min, :subject_batch_burst_sec,
                :tokens, :stop_grace_ms, :kill_grace_ms, :max_moves, :health_interval_s

    def self.from_env(env = ENV)
      new(env)
    end

    # +engine_command+ overrides ENGINE_PATH with an argv array (used by tests).
    def initialize(env = {}, engine_command: nil)
      @env = env
      @engine_command = (engine_command || [env.fetch('ENGINE_PATH', 'stockfish')]).dup.freeze
      read_engine_settings
      read_budget_settings
      @lanes = { interactive: interactive_limits, batch: batch_limits }.freeze
      @tokens = parse_tokens(env.fetch('API_TOKENS', ''))
      freeze
    end

    def lane(name)
      @lanes.fetch(name)
    end

    private

    def read_engine_settings
      @pool_size = int('POOL_SIZE', 2, 1..16)
      # Interactive requests always keep at least this many workers to themselves.
      # With a single worker nothing can be reserved, or batch work could never run.
      @reserved_interactive = [int('RESERVED_INTERACTIVE', 1, 0..15), @pool_size - 1].min
      @threads = int('THREADS', 1, 1..8)
      @hash_mb = int('HASH_MB', 16, 1..1024)
      @stop_grace_ms = int('STOP_GRACE_MS', 250, 0..10_000)
      @kill_grace_ms = int('KILL_GRACE_MS', 1000, 100..10_000)
      @max_moves = int('MAX_MOVES', 600, 0..2000)
      @health_interval_s = int('HEALTH_INTERVAL_S', 30, 1..3600)
    end

    def read_budget_settings
      @global_engine_sec_per_min = int('GLOBAL_ENGINE_SEC_PER_MIN', 90, 1..100_000)
      # Per-subject quotas, one per lane. Interactive requests are short; a
      # whole-game analysis (batch) needs about a minute of engine time.
      @subject_engine_sec_per_min = int('SUBJECT_ENGINE_SEC_PER_MIN', 20, 1..100_000)
      @subject_burst_sec = int('SUBJECT_BURST_SEC', 10, 1..100_000)
      @subject_batch_engine_sec_per_min = int('SUBJECT_BATCH_ENGINE_SEC_PER_MIN', 60, 1..100_000)
      @subject_batch_burst_sec = int('SUBJECT_BATCH_BURST_SEC', 120, 1..100_000)
    end

    def interactive_limits
      LaneLimits.new(
        default_depth: int('INTERACTIVE_DEFAULT_DEPTH', 16, 1..60),
        max_depth: int('INTERACTIVE_MAX_DEPTH', 18, 1..60),
        max_movetime_ms: int('INTERACTIVE_MAX_MOVETIME_MS', 2000, 10..600_000),
        max_nodes: int('INTERACTIVE_MAX_NODES', 2_000_000, 1..10_000_000_000),
        max_multipv: int('INTERACTIVE_MAX_MULTIPV', 3, 1..10),
        queue_max: int('INTERACTIVE_QUEUE_MAX', 8, 0..1000),
        queue_wait_s: int('INTERACTIVE_QUEUE_WAIT_S', 5, 0..600)
      ).freeze
    end

    def batch_limits
      LaneLimits.new(
        default_depth: int('BATCH_DEFAULT_DEPTH', 14, 1..60),
        max_depth: int('BATCH_MAX_DEPTH', 14, 1..60),
        max_movetime_ms: int('BATCH_MAX_MOVETIME_MS', 400, 10..600_000),
        max_nodes: int('BATCH_MAX_NODES', 1_000_000, 1..10_000_000_000),
        max_multipv: int('BATCH_MAX_MULTIPV', 3, 1..10),
        queue_max: int('BATCH_QUEUE_MAX', 4, 0..1000),
        queue_wait_s: int('BATCH_QUEUE_WAIT_S', 30, 0..600)
      ).freeze
    end

    def int(key, default, range)
      raw = @env.fetch(key, default)
      value = Integer(raw.to_s, 10)
      raise ArgumentError, "#{key} must be within #{range}, got #{value}" unless range.cover?(value)

      value
    rescue TypeError, ArgumentError => e
      raise ArgumentError, "Invalid #{key}=#{raw.inspect}: #{e.message}"
    end

    def parse_tokens(raw)
      tokens = raw.split(',').map(&:strip).reject(&:empty?)
      short = tokens.find { |token| token.length < MIN_TOKEN_LENGTH }
      raise ArgumentError, "API_TOKENS entries must be at least #{MIN_TOKEN_LENGTH} characters" if short

      tokens.freeze
    end
  end
end
