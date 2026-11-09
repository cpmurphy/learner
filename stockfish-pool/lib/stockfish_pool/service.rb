# frozen_string_literal: true

require 'logger'
require_relative 'budgets'
require_relative 'engine_worker'
require_relative 'pool'

module StockfishPool
  # The caller's subject has used up its share of engine time.
  class QuotaExceeded < StandardError
    attr_reader :retry_after

    def initialize(message = 'Engine time quota exceeded', retry_after: 1)
      super(message)
      @retry_after = retry_after
    end
  end

  # Counts refused requests and logs them at most once a minute, so throttling
  # is visible without one log line per refusal. The first refusal after a
  # quiet minute is logged at once; later ones are summed into the next line.
  class RefusalLog
    INTERVAL_S = 60

    def initialize(logger:, clock:)
      @logger = logger
      @clock = clock
      @counts = Hash.new(0)
      @logged_at = nil
      @mutex = Mutex.new
    end

    def record(reason, lane)
      @mutex.synchronize do
        @counts["#{reason} (#{lane})"] += 1
        now = @clock.call
        flush(now) if @logged_at.nil? || now - @logged_at >= INTERVAL_S
      end
    end

    private

    def flush(now)
      summary = @counts.map { |key, count| "#{count} #{key}" }.join(', ')
      window = @logged_at ? " in the last #{(now - @logged_at).round}s" : ''
      @logger.warn("stockfish-pool: refused #{summary}#{window}")
      @counts.clear
      @logged_at = now
    end
  end

  # Runs searches subject to, in order: the per-subject quota for the
  # request's lane, the global engine-time budget, and the pool's lanes and
  # queues. Engine time is charged after each search, including searches that
  # fail.
  class Service
    attr_reader :config

    def self.build(config, logger: Logger.new($stdout))
      pool = Pool.new(config: config, logger: logger,
                      worker_factory: -> { EngineWorker.new(config: config) })
      new(config: config, pool: pool, logger: logger)
    end

    def self.default_quotas(config, clock)
      {
        interactive: SubjectQuota.new(rate_per_min: config.subject_engine_sec_per_min,
                                      burst_s: config.subject_burst_sec, clock: clock),
        batch: SubjectQuota.new(rate_per_min: config.subject_batch_engine_sec_per_min,
                                burst_s: config.subject_batch_burst_sec, clock: clock)
      }
    end

    # rubocop:disable Metrics/ParameterLists
    def initialize(config:, pool:, clock: MONOTONIC_CLOCK, logger: Logger.new($stdout),
                   budget: GlobalBudget.new(limit_s: config.global_engine_sec_per_min, clock: clock),
                   quotas: Service.default_quotas(config, clock))
      # rubocop:enable Metrics/ParameterLists
      @config = config
      @pool = pool
      @clock = clock
      @budget = budget
      @quotas = quotas
      @refusals = RefusalLog.new(logger: logger, clock: clock)
    end

    def quota(lane)
      @quotas.fetch(lane)
    end

    def start(**options)
      @pool.start(**options)
      self
    end

    def shutdown
      @pool.shutdown
    end

    def analyze(request)
      check_quota(request)
      raise Busy.new('Global engine time budget exhausted', retry_after: @budget.retry_after) unless @budget.available?

      started = @clock.call
      result = @pool.with_worker(request.lane) { |worker| timed_search(worker, request) }
      result.merge(lane: request.lane, applied: request.applied, ms: ((@clock.call - started) * 1000).round)
    rescue QuotaExceeded, Busy => e
      @refusals.record(e.is_a?(QuotaExceeded) ? 'quota_exceeded' : 'busy', request.lane)
      raise
    end

    def health
      stats = @pool.stats
      up = stats[:workers].count { |worker| worker[:state] != :down }
      {
        status: health_status(up, stats[:workers].size),
        workers: stats[:workers],
        waiting: stats[:waiting],
        budget: { used_s: @budget.used_s.round(1), limit_s: @config.global_engine_sec_per_min }
      }
    end

    private

    def check_quota(request)
      subject = request.subject
      return if subject.nil? || quota(request.lane).allow?(subject)

      raise QuotaExceeded.new("Engine time quota exceeded (#{request.lane} lane)",
                              retry_after: quota(request.lane).retry_after(subject))
    end

    def timed_search(worker, request)
      search_started = @clock.call
      worker.search(request)
    ensure
      elapsed = @clock.call - search_started
      @budget.charge(elapsed)
      quota(request.lane).charge(request.subject, elapsed) if request.subject
    end

    def health_status(up_count, total)
      return 'down' if up_count.zero?

      up_count == total ? 'ok' : 'degraded'
    end
  end
end
