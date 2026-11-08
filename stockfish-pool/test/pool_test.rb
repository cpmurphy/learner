# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'support/fake_worker'

class PoolTest < Minitest::Test
  include TestSupport

  def build_pool(overrides = {}, clock: StockfishPool::MONOTONIC_CLOCK, factory: -> { FakeWorker.new })
    @config = config({ 'INTERACTIVE_QUEUE_WAIT_S' => '2', 'BATCH_QUEUE_WAIT_S' => '2' }.merge(overrides))
    @pool = StockfishPool::Pool.new(config: @config, worker_factory: factory, clock: clock, logger: null_logger)
    @pool.start(supervise: false)
  end

  def teardown
    @threads&.each { |thread| thread.kill.join(1) }
    @pool&.shutdown
  end

  # Runs a search on +lane+ in a thread, blocking in the worker until +gate+ is released.
  def hold(lane, gate)
    queue = Queue.new
    @threads ||= []
    @threads << Thread.new do
      @pool.with_worker(lane) do |worker|
        worker.gate = gate
        queue << worker
        worker.search(request(@config))
      ensure
        worker.gate = nil
      end
    end
    queue.pop
  end

  def wait_until(timeout = 2)
    deadline = Time.now + timeout
    sleep 0.01 until yield || Time.now > deadline
  end

  def test_interactive_prefers_reserved_worker
    build_pool
    reserved = @pool.with_worker(:interactive) { |worker| worker }

    assert_equal reserved, @pool.with_worker(:interactive) { |worker| worker }
    refute_equal reserved, @pool.with_worker(:batch) { |worker| worker }
  end

  def test_batch_never_uses_reserved_worker
    build_pool({ 'BATCH_QUEUE_WAIT_S' => '0' })
    gate = Queue.new
    hold(:batch, gate)

    assert_raises(StockfishPool::Busy) { @pool.with_worker(:batch) { flunk 'should not run' } }
    assert_equal 'ok', @pool.with_worker(:interactive) { 'ok' }
    gate << :go
  end

  def test_interactive_waiter_beats_batch_waiter
    build_pool
    gates = [Queue.new, Queue.new]
    gates.each { |gate| hold(:interactive, gate) }
    order = Queue.new
    @threads << Thread.new { @pool.with_worker(:batch) { order << :batch } }
    wait_until { @pool.stats[:waiting][:batch] == 1 }
    @threads << Thread.new { @pool.with_worker(:interactive) { order << :interactive } }
    wait_until { @pool.stats[:waiting][:interactive] == 1 }

    gates[1] << :go # frees the shared worker
    first = order.pop
    gates[0] << :go

    assert_equal :interactive, first
    assert_equal :batch, order.pop
  end

  def test_full_queue_is_rejected_immediately
    build_pool({ 'INTERACTIVE_QUEUE_MAX' => '0' })
    gates = [Queue.new, Queue.new]
    gates.each { |gate| hold(:interactive, gate) }

    error = assert_raises(StockfishPool::Busy) { @pool.with_worker(:interactive) { nil } }
    assert_match(/queue is full/, error.message)
    gates.each { |gate| gate << :go }
  end

  def test_crashed_worker_is_restarted
    build_pool
    assert_raises(StockfishPool::WorkerCrashed) do
      @pool.with_worker(:interactive) do |worker|
        worker.failure = StockfishPool::WorkerCrashed.new('boom')
        worker.search(request(@config))
      end
    end

    assert_equal :down, @pool.stats[:workers][0][:state]
    @pool.supervise_once

    assert_equal(%i[idle idle], @pool.stats[:workers].map { |worker| worker[:state] })
    assert_equal 1, @pool.stats[:workers][0][:restarts]
  end

  def test_interrupted_search_does_not_reuse_worker
    build_pool({ 'POOL_SIZE' => '1' })
    interrupted = nil
    assert_raises(RuntimeError) do
      @pool.with_worker(:interactive) do |worker|
        interrupted = worker
        raise 'request thread interrupted mid-search'
      end
    end

    refute_predicate interrupted, :alive?
    assert_equal :down, @pool.stats[:workers][0][:state]
  end

  def test_failed_start_backs_off
    now = 100.0
    attempts = 0
    factory = lambda do
      attempts += 1
      FakeWorker.new(fail_start: attempts <= 2)
    end
    build_pool({ 'POOL_SIZE' => '1' }, clock: -> { now }, factory: factory)

    assert_equal :down, @pool.stats[:workers][0][:state]
    @pool.supervise_once # retry_at is 1s away
    now += 1
    @pool.supervise_once # second failure, retry in 2s
    now += 1.5
    @pool.supervise_once

    assert_equal 2, attempts
    now += 1
    @pool.supervise_once

    assert_equal :idle, @pool.stats[:workers][0][:state]
  end

  def test_unavailable_when_no_worker_can_serve_lane
    build_pool({ 'POOL_SIZE' => '1' }, factory: -> { FakeWorker.new(fail_start: true) })

    assert_raises(StockfishPool::Unavailable) { @pool.with_worker(:interactive) { nil } }
  end

  def test_dead_idle_worker_is_never_handed_out
    build_pool
    reserved = @pool.with_worker(:interactive) { |worker| worker }
    reserved.kill # e.g. the kernel OOM-killed the idle engine

    refute_equal reserved, @pool.with_worker(:interactive) { |worker| worker }
    assert_equal :down, @pool.stats[:workers][0][:state]
    @pool.supervise_once

    assert_equal :idle, @pool.stats[:workers][0][:state]
  end

  def test_unresponsive_idle_worker_is_replaced
    now = 100.0
    build_pool({ 'POOL_SIZE' => '1', 'HEALTH_INTERVAL_S' => '30' }, clock: -> { now })
    original = @pool.with_worker(:interactive) { |worker| worker }
    original.healthy = false
    now += 31
    @pool.supervise_once # health check fails, worker marked down

    refute_predicate original, :alive?
    @pool.supervise_once # restarted

    refute_equal original, @pool.with_worker(:interactive) { |worker| worker }
  end
end
