# frozen_string_literal: true

require 'logger'
require_relative 'budgets'
require_relative 'engine_worker'
require_relative 'pool_recovery'

module StockfishPool
  # No worker became free in time, or the lane's queue is full.
  class Busy < StandardError
    attr_reader :retry_after

    def initialize(message = 'All engine workers are busy', retry_after: 1)
      super(message)
      @retry_after = retry_after
    end
  end

  # No worker that can serve the lane is running.
  class Unavailable < StandardError; end

  # A fixed set of engine workers with two lanes:
  # - interactive requests may use any worker, preferring the reserved ones;
  # - batch requests may use only unreserved workers, and only while no
  #   interactive request is waiting.
  #
  # A supervisor thread restarts crashed workers with exponential backoff and
  # health-checks idle ones. The pool never grows beyond its configured size.
  class Pool
    include PoolRecovery

    Slot = Struct.new(:id, :reserved, :worker, :state, :starts, :failures, :retry_at, :checked_at,
                      keyword_init: true)

    MAX_BACKOFF_S = 30

    # rubocop:disable Metrics/ParameterLists
    def initialize(config:, worker_factory:, clock: MONOTONIC_CLOCK, logger: Logger.new($stdout),
                   tick_s: 0.5, max_backoff_s: MAX_BACKOFF_S)
      # rubocop:enable Metrics/ParameterLists
      @config = config
      @worker_factory = worker_factory
      @clock = clock
      @logger = logger
      @tick_s = tick_s
      @max_backoff_s = max_backoff_s
      @slots = Array.new(config.pool_size) { |index| new_slot(index) }
      @waiting = { interactive: 0, batch: 0 }
      @mutex = Mutex.new
      @cond = ConditionVariable.new
      @stopping = false
    end

    # Starts every worker (synchronously, so the service is ready once this
    # returns) and, unless +supervise+ is false, the supervisor thread.
    def start(supervise: true)
      due = @mutex.synchronize { claim_due_slots }
      due.each { |slot| restart(slot) }
      @supervisor = Thread.new { supervise_loop } if supervise
      self
    end

    # Any exit other than a normal return (an engine error, but also a killed
    # request thread) may leave unread engine output behind, which the next
    # caller would read as its own result. Such workers are replaced, not reused.
    def with_worker(lane)
      slot = checkout(lane)
      completed = false
      begin
        result = yield slot.worker
        completed = true
        result
      ensure
        checkin(slot, failed: !completed || !slot.worker.alive?)
      end
    end

    # One supervisor pass: restart workers that are due, then health-check idle ones.
    def supervise_once
      due = @mutex.synchronize { claim_due_slots }
      due.each { |slot| restart(slot) }
      check_health
    end

    def stats
      @mutex.synchronize do
        {
          workers: @slots.map do |slot|
            { id: slot.id, reserved: slot.reserved, state: slot.state, restarts: [slot.starts - 1, 0].max }
          end,
          waiting: @waiting.dup
        }
      end
    end

    def shutdown
      @stopping = true
      @supervisor&.join(5)
      workers = @mutex.synchronize do
        @slots.each { |slot| slot.state = :down }
        @cond.broadcast
        @slots.map(&:worker)
      end
      workers.compact.each(&:stop)
    end

    private

    def new_slot(index)
      Slot.new(id: index + 1, reserved: index < @config.reserved_interactive, state: :down,
               starts: 0, failures: 0, retry_at: 0, checked_at: 0)
    end

    def checkout(lane)
      limits = @config.lane(lane)
      @mutex.synchronize do
        raise Unavailable, "No #{lane} engine workers are running" unless serviceable?(lane)

        slot = take(lane)
        next slot if slot
        raise Busy, "The #{lane} queue is full" if @waiting[lane] >= limits.queue_max

        wait_for_slot(lane, @clock.call + limits.queue_wait_s)
      end
    end

    # Called with @mutex held.
    def wait_for_slot(lane, deadline)
      @waiting[lane] += 1
      loop do
        remaining = deadline - @clock.call
        raise Busy, "Timed out waiting for a #{lane} engine worker" if remaining <= 0

        @cond.wait(@mutex, remaining)
        raise Unavailable, "No #{lane} engine workers are running" unless serviceable?(lane)

        slot = take(lane)
        return slot if slot
      end
    ensure
      @waiting[lane] -= 1
      # A departing interactive waiter may unblock a batch waiter.
      @cond.broadcast if lane == :interactive
    end

    # Called with @mutex held.
    def take(lane)
      slot = candidate_for(lane)
      slot.state = :busy if slot
      slot
    end

    # Called with @mutex held.
    def candidate_for(lane)
      reap_dead_idle
      idle = @slots.select { |slot| slot.state == :idle }
      return idle.find(&:reserved) || idle.first if lane == :interactive
      return nil if @waiting[:interactive].positive?

      idle.reject(&:reserved).first
    end

    # Called with @mutex held.
    def serviceable?(lane)
      candidates = lane == :batch ? @slots.reject(&:reserved) : @slots
      candidates.any? { |slot| slot.state != :down }
    end

    def checkin(slot, failed:)
      slot.worker.kill if failed
      @mutex.synchronize do
        if failed
          mark_down(slot)
        else
          slot.state = :idle
        end
        @cond.broadcast
      end
    end
  end
end
