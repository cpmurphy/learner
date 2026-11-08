# frozen_string_literal: true

module StockfishPool
  # Restart and health-check logic for Pool: crashed or unresponsive workers
  # are marked down and restarted with exponential backoff. Methods documented
  # as "called with @mutex held" must only run inside the pool's lock.
  module PoolRecovery
    private

    # Called with @mutex held.
    def mark_down(slot)
      slot.state = :down
      slot.retry_at = @clock.call
      @logger.warn("stockfish-pool: worker #{slot.id} failed; scheduling restart")
    end

    # Called with @mutex held. Marks due slots as starting so only one thread restarts each.
    def claim_due_slots
      now = @clock.call
      due = @slots.select { |slot| slot.state == :down && slot.retry_at <= now }
      due.each { |slot| slot.state = :starting }
      due
    end

    def restart(slot)
      worker = @worker_factory.call.start
      @mutex.synchronize do
        slot.worker = worker
        slot.starts += 1
        slot.failures = 0
        slot.checked_at = @clock.call
        slot.state = @stopping ? :down : :idle
        @cond.broadcast
      end
      worker.stop if @stopping
    rescue WorkerError => e
      schedule_retry(slot, e)
    end

    def schedule_retry(slot, error)
      @mutex.synchronize do
        slot.failures += 1
        delay = [2**(slot.failures - 1), @max_backoff_s].min
        slot.retry_at = @clock.call + delay
        slot.state = :down
        @logger.error("stockfish-pool: worker #{slot.id} failed to start (#{error.message}); retrying in #{delay}s")
        @cond.broadcast
      end
    end

    # Called with @mutex held. An idle engine that died (OOM kill, crash) is
    # noticed here, a cheap check that needs no engine I/O, instead of being
    # handed to the next caller.
    def reap_dead_idle
      @slots.each do |slot|
        next unless slot.state == :idle && !slot.worker.alive?

        slot.worker.kill
        mark_down(slot)
      end
    end

    def check_health
      due = @mutex.synchronize do
        reap_dead_idle
        cutoff = @clock.call - @config.health_interval_s
        @slots.select { |slot| slot.state == :idle && slot.checked_at <= cutoff }
              .each { |slot| slot.state = :checking }
      end
      due.each { |slot| finish_health_check(slot, slot.worker.responsive?) }
    end

    def finish_health_check(slot, healthy)
      slot.worker.kill unless healthy
      @mutex.synchronize do
        slot.checked_at = @clock.call
        healthy ? slot.state = :idle : mark_down(slot)
        @cond.broadcast
      end
    end

    def supervise_loop
      until @stopping
        begin
          supervise_once
        rescue StandardError => e
          @logger.error("stockfish-pool: supervisor error: #{e.class}: #{e.message}")
        end
        sleep @tick_s
      end
    end
  end
end
