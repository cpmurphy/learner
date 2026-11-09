# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/analysis_slots'

class AnalysisSlotsTest < Minitest::Test
  def test_runs_the_block_in_a_free_slot
    slots = AnalysisSlots.new(1)

    assert_equal([true, 42], slots.run { 42 })
    assert_equal 0, slots.in_use
  end

  def test_refuses_without_running_when_full
    slots = AnalysisSlots.new(1)
    ran_inner = :not_called
    outer = slots.run { ran_inner = slots.run { flunk 'must not run' } }

    assert_equal [true, [false, nil]], outer
    assert_equal [false, nil], ran_inner
  end

  def test_releases_the_slot_when_the_block_raises
    slots = AnalysisSlots.new(1)
    assert_raises(RuntimeError) { slots.run { raise 'boom' } }

    assert_equal 0, slots.in_use
    assert_equal([true, :ok], slots.run { :ok })
  end

  def test_limit_must_be_positive
    assert_raises(ArgumentError) { AnalysisSlots.new(0) }
  end
end
