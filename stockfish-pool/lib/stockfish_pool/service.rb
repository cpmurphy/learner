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

  # Runs searches subject to, in order: the per-subject quota, the global
  # engine-time budget, and the pool's lanes and queues. Engine time is charged
  # after each search, including searches that fail.
  class Service
    attr_reader :config

    def self.build(config, logger: Logger.new($stdout))
      pool = Pool.new(config: config, logger: logger,
                      worker_factory: -> { EngineWorker.new(config: config) })
      new(config: config, pool: pool)
    end

    def initialize(config:, pool:, clock: MONOTONIC_CLOCK,
                   budget: GlobalBudget.new(limit_s: config.global_engine_sec_per_min, clock: clock),
                   quota: SubjectQuota.new(rate_per_min: config.subject_engine_sec_per_min,
                                           burst_s: config.subject_burst_sec, clock: clock))
      @config = config
      @pool = pool
      @clock = clock
      @budget = budget
      @quota = quota
    end

    def start(**options)
      @pool.start(**options)
      self
    end

    def shutdown
      @pool.shutdown
    end

    def analyze(request)
      check_quota(request.subject)
      raise Busy.new('Global engine time budget exhausted', retry_after: @budget.retry_after) unless @budget.available?

      started = @clock.call
      result = @pool.with_worker(request.lane) { |worker| timed_search(worker, request) }
      result.merge(lane: request.lane, applied: request.applied, ms: ((@clock.call - started) * 1000).round)
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

    def check_quota(subject)
      return if subject.nil? || @quota.allow?(subject)

      raise QuotaExceeded.new(retry_after: @quota.retry_after(subject))
    end

    def timed_search(worker, request)
      search_started = @clock.call
      worker.search(request)
    ensure
      elapsed = @clock.call - search_started
      @budget.charge(elapsed)
      @quota.charge(request.subject, elapsed) if request.subject
    end

    def health_status(up_count, total)
      return 'down' if up_count.zero?

      up_count == total ? 'ok' : 'degraded'
    end
  end
end
