# frozen_string_literal: true

# A small, thread-safe, bounded in-memory store for Rack::Attack counters.
# Enough for a single Puma process; it implements the methods Rack::Attack
# calls (increment, read, write, delete, delete_matched).
class MemoryRateStore
  DEFAULT_MAX_ENTRIES = 50_000

  def initialize(max_entries: DEFAULT_MAX_ENTRIES, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    @max_entries = max_entries
    @clock = clock
    @entries = {} # key => [value, expires_at]
    @mutex = Mutex.new
  end

  def increment(key, amount = 1, expires_in: nil)
    @mutex.synchronize do
      value, expires_at = live_entry(key)
      value = value.to_i + amount
      store(key, value, expires_at || expiry(expires_in))
      value
    end
  end

  def read(key)
    @mutex.synchronize { live_entry(key)&.first }
  end

  def write(key, value, expires_in: nil)
    @mutex.synchronize { store(key, value, expiry(expires_in)) }
    value
  end

  def delete(key)
    @mutex.synchronize { @entries.delete(key)&.first }
  end

  def delete_matched(pattern)
    @mutex.synchronize { @entries.delete_if { |key, _| pattern.match?(key) } }
  end

  def size
    @mutex.synchronize { @entries.size }
  end

  private

  def live_entry(key)
    entry = @entries[key]
    return nil unless entry
    return entry if entry[1].nil? || entry[1] > @clock.call

    @entries.delete(key)
    nil
  end

  def store(key, value, expires_at)
    @entries[key] = [value, expires_at]
    prune if @entries.size > @max_entries
  end

  def expiry(expires_in)
    expires_in ? @clock.call + expires_in : nil
  end

  # Drops expired counters; if that is not enough, the ones expiring soonest
  # (they matter least) until the store is back to three quarters full.
  def prune
    drop_expired
    excess = @entries.size - (@max_entries * 3 / 4)
    return unless excess.positive?

    @entries.min_by(excess) { |_, (_, expires_at)| expires_at || Float::INFINITY }
            .map(&:first).each { |key| @entries.delete(key) }
  end

  def drop_expired
    now = @clock.call
    @entries.delete_if { |_, (_, expires_at)| expires_at && expires_at <= now }
  end
end
