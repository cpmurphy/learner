# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/memory_rate_store'

class MemoryRateStoreTest < Minitest::Test
  def setup
    @now = 100.0
    @store = MemoryRateStore.new(max_entries: 8, clock: -> { @now })
  end

  def test_increment_counts_until_expiry
    assert_equal 1, @store.increment('k', 1, expires_in: 10)
    assert_equal 2, @store.increment('k', 1, expires_in: 10)
    @now += 11

    assert_nil @store.read('k')
    assert_equal 1, @store.increment('k', 1, expires_in: 10)
  end

  def test_increment_keeps_the_first_expiry
    @store.increment('k', 1, expires_in: 10)
    @now += 9
    @store.increment('k', 1, expires_in: 10)
    @now += 2

    assert_nil @store.read('k')
  end

  def test_write_read_delete_and_delete_matched
    @store.write('rack::attack:a', 5, expires_in: 10)
    @store.write('other', 1)

    assert_equal 5, @store.read('rack::attack:a')
    @store.delete_matched(/rack::attack/)

    assert_nil @store.read('rack::attack:a')
    assert_equal 1, @store.delete('other')
  end

  def test_stays_bounded
    50.times { |i| @store.increment("k#{i}", 1, expires_in: 100 + i) }

    assert_operator @store.size, :<=, 8
    assert_equal 1, @store.read('k49'), 'keeps the counters that expire last'
  end
end
