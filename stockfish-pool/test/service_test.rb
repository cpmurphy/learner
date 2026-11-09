# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'support/fake_worker'
require 'stringio'

class ServiceTest < Minitest::Test
  include TestSupport

  def setup
    @now = 1000.0
    @log = StringIO.new
    @config = config
    pool = StockfishPool::Pool.new(config: @config, worker_factory: -> { FakeWorker.new }, logger: null_logger)
    @service = StockfishPool::Service.new(config: @config, pool: pool, clock: -> { @now }, logger: Logger.new(@log))
    @service.start(supervise: false)
  end

  def teardown
    @service.shutdown
  end

  def analyze(lane)
    @service.analyze(request(@config, 'lane' => lane.to_s, 'subject' => 'visitor-1'))
  end

  def test_lanes_have_separate_quotas
    @service.quota(:interactive).charge('visitor-1', 60)

    assert_raises(StockfishPool::QuotaExceeded) { analyze(:interactive) }
    assert_equal 'e2e4', analyze(:batch)[:bestmove], 'hints used up must not block whole-game analysis'
  end

  def test_batch_quota_fits_a_whole_game
    # A 40-move game on a slow CPU: 160 searches of up to 0.4 s each.
    @service.quota(:batch).charge('visitor-1', 60)

    assert_equal 'e2e4', analyze(:batch)[:bestmove]
    @service.quota(:batch).charge('visitor-1', 60)

    assert_raises(StockfishPool::QuotaExceeded) { analyze(:batch) }
  end

  def test_quota_message_names_the_lane
    @service.quota(:batch).charge('visitor-1', 500)
    error = assert_raises(StockfishPool::QuotaExceeded) { analyze(:batch) }

    assert_match(/batch lane/, error.message)
  end

  def test_refusals_are_logged_at_most_once_a_minute
    @service.quota(:interactive).charge('visitor-1', 600)

    3.times { assert_raises(StockfishPool::QuotaExceeded) { analyze(:interactive) } }

    assert_equal 1, @log.string.scan('refused').size, 'first refusal logged at once, the rest held back'

    @now += 61
    assert_raises(StockfishPool::QuotaExceeded) { analyze(:interactive) }

    assert_equal 2, @log.string.scan('refused').size
    assert_match(/refused 3 quota_exceeded \(interactive\) in the last 61s/, @log.string)
  end
end
