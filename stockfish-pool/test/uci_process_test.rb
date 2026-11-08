# frozen_string_literal: true

require_relative 'test_helper'

class UciProcessTest < Minitest::Test
  include TestSupport

  def setup
    @process = StockfishPool::UciProcess.new([RbConfig.ruby, FAKE_ENGINE, 'normal'])
  end

  def teardown
    @process.kill
  end

  def test_refuses_commands_with_line_breaks
    assert_raises(ArgumentError) { @process.write_line("isready\nsetoption name Threads value 1024") }
    assert_raises(ArgumentError) { @process.write_line("isready\rquit") }
  end

  def test_read_until_times_out_instead_of_blocking
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    refute @process.read_until('never', started + 0.1)
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 0.5
  end

  def test_kill_terminates_the_process
    @process.kill

    refute_predicate @process, :alive?
  end
end
