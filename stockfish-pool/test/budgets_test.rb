# frozen_string_literal: true

require_relative 'test_helper'

class BudgetsTest < Minitest::Test
  def setup
    @now = 1000.0
    @clock = -> { @now }
  end

  def test_global_budget_is_a_sliding_window
    budget = StockfishPool::GlobalBudget.new(limit_s: 10, clock: @clock)
    budget.charge(6)
    @now += 30
    budget.charge(5)

    refute_predicate budget, :available?
    assert_equal 30, budget.retry_after
    @now += 31

    assert_predicate budget, :available?
    assert_in_delta 5.0, budget.used_s
  end

  def test_subject_quota_refills_over_time
    quota = StockfishPool::SubjectQuota.new(rate_per_min: 60, burst_s: 10, clock: @clock)
    quota.charge('ip-a', 12)

    refute quota.allow?('ip-a')
    assert quota.allow?('ip-b')
    assert_equal 2, quota.retry_after('ip-a')
    @now += 3

    assert quota.allow?('ip-a')
  end

  def test_subject_quota_bounds_memory
    quota = StockfishPool::SubjectQuota.new(rate_per_min: 60, burst_s: 10, clock: @clock, max_subjects: 3)
    %w[a b c d e].each do |subject|
      quota.charge(subject, 20)
      @now += 1
    end

    assert_operator quota.instance_variable_get(:@buckets).size, :<=, 3
    refute quota.allow?('e')
  end
end
