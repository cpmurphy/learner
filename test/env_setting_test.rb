# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/env_setting'

class EnvSettingTest < Minitest::Test
  def test_blank_values_count_as_unset
    env = { 'EMPTY' => '', 'SPACES' => '  ', 'SET' => ' value ' }

    assert_nil EnvSetting.get('EMPTY', env)
    assert_nil EnvSetting.get('SPACES', env)
    assert_nil EnvSetting.get('MISSING', env)
    assert_equal 'value', EnvSetting.get('SET', env)
  end

  def test_integers
    env = { 'EMPTY' => '', 'N' => '42', 'BAD' => 'lots' }

    assert_equal 7, EnvSetting.integer('EMPTY', 7, env)
    assert_equal 42, EnvSetting.integer('N', 7, env)
    assert_raises(ArgumentError) { EnvSetting.integer('BAD', 7, env) }
  end
end
