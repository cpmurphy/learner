# frozen_string_literal: true

module StockfishPool
  MONOTONIC_CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

  # Caps total engine time across all callers within a sliding window, so a
  # distributed flood still cannot use more than the configured CPU share.
  class GlobalBudget
    WINDOW_S = 60.0

    def initialize(limit_s:, clock: MONOTONIC_CLOCK)
      @limit_s = limit_s.to_f
      @clock = clock
      @entries = []
      @used_s = 0.0
      @mutex = Mutex.new
    end

    def available?
      @mutex.synchronize do
        prune
        @used_s < @limit_s
      end
    end

    def charge(seconds)
      @mutex.synchronize do
        @entries << [@clock.call, seconds]
        @used_s += seconds
      end
    end

    def used_s
      @mutex.synchronize do
        prune
        @used_s
      end
    end

    # Seconds until the oldest charge leaves the window.
    def retry_after
      @mutex.synchronize do
        prune
        oldest = @entries.first
        oldest ? [(oldest[0] + WINDOW_S - @clock.call).ceil, 1].max : 1
      end
    end

    private

    def prune
      cutoff = @clock.call - WINDOW_S
      while (entry = @entries.first) && entry[0] <= cutoff
        @entries.shift
        @used_s -= entry[1]
      end
    end
  end

  # Per-subject (for example, a hashed client IP) token bucket measured in
  # engine-seconds. A subject may start a search while it has any balance left;
  # the actual time used is charged afterwards.
  class SubjectQuota
    MAX_SUBJECTS = 10_000

    def initialize(rate_per_min:, burst_s:, clock: MONOTONIC_CLOCK, max_subjects: MAX_SUBJECTS)
      @rate_per_s = rate_per_min / 60.0
      @capacity = burst_s.to_f
      @clock = clock
      @max_subjects = max_subjects
      @buckets = {}
      @mutex = Mutex.new
    end

    def allow?(subject)
      @mutex.synchronize { balance(subject).positive? }
    end

    def charge(subject, seconds)
      @mutex.synchronize do
        @buckets[subject] = [balance(subject) - seconds, @clock.call]
      end
    end

    # Seconds until the subject's balance is positive again (at least 1).
    def retry_after(subject)
      @mutex.synchronize do
        deficit = [-balance(subject), 0.0].max
        [(deficit / @rate_per_s).ceil, 1].max
      end
    end

    private

    # Refills the subject's bucket for elapsed time and returns its balance.
    def balance(subject)
      now = @clock.call
      tokens, updated_at = @buckets.fetch(subject) do
        evict if @buckets.size >= @max_subjects
        [@capacity, now]
      end
      tokens = [tokens + ((now - updated_at) * @rate_per_s), @capacity].min
      @buckets[subject] = [tokens, now]
      tokens
    end

    # Makes room for one more subject. Full buckets carry no information, so
    # they go first; then the stalest.
    def evict
      @buckets.delete_if { |_subject, (tokens, _at)| tokens >= @capacity }
      excess = @buckets.size - @max_subjects + 1
      return unless excess.positive?

      stalest = @buckets.min_by(excess) { |_subject, (_tokens, at)| at }
      stalest.map(&:first).each { |subject| @buckets.delete(subject) }
    end
  end
end
