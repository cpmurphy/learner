# frozen_string_literal: true

require_relative 'test_helper'

class ConfigTest < Minitest::Test
  def test_defaults_fit_a_small_vps
    config = StockfishPool::Config.new

    assert_equal 2, config.pool_size
    assert_equal 1, config.reserved_interactive
    assert_equal 1, config.threads
    assert_equal 18, config.lane(:interactive).max_depth
    assert_equal 14, config.lane(:batch).max_depth
  end

  def test_single_worker_reserves_nothing
    assert_equal 0, StockfishPool::Config.new({ 'POOL_SIZE' => '1' }).reserved_interactive
  end

  def test_rejects_out_of_range_and_garbage
    range_error = assert_raises(ArgumentError) { StockfishPool::Config.new({ 'POOL_SIZE' => '0' }) }
    garbage_error = assert_raises(ArgumentError) { StockfishPool::Config.new({ 'HASH_MB' => 'lots' }) }

    assert_match(/POOL_SIZE/, range_error.message)
    assert_match(/HASH_MB/, garbage_error.message)
  end

  def test_tokens_are_split_and_must_be_long
    config = StockfishPool::Config.new({ 'API_TOKENS' => "#{'a' * 24}, #{'b' * 30}" })

    assert_equal ['a' * 24, 'b' * 30], config.tokens
    assert_raises(ArgumentError) { StockfishPool::Config.new({ 'API_TOKENS' => 'short' }) }
  end

  def test_engine_path_is_a_single_argument
    config = StockfishPool::Config.new({ 'ENGINE_PATH' => '/usr/bin/stockfish --evil' })

    assert_equal ['/usr/bin/stockfish --evil'], config.engine_command
  end
end
