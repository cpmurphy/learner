# frozen_string_literal: true

require_relative 'test_helper'
require 'open3'

# Boots the app in a fresh process with settings left blank, the way the
# deploy/env templates leave them (`KEY=`), and asks it for /api/session.
class AppBootEnvTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  PROBE = <<~RUBY
    require './app'
    require 'rack/mock'
    puts Rack::MockRequest.new(LearnerApp.new).get('/api/session', 'HTTP_HOST' => 'localhost').body
  RUBY

  def boot(env)
    Open3.capture2e({ 'APP_ENV' => 'production', 'RACK_ENV' => 'production', 'RATE_LIMITS' => 'off' }.merge(env),
                    RbConfig.ruby, '-e', PROBE, chdir: ROOT)
  end

  def test_blank_settings_boot_with_writes_disabled
    blank = %w[OWNER_PASSWORD_HASH SESSION_SECRET ENGINE_SUBJECT_SECRET MAX_SESSIONS TRUSTED_PROXIES
               MAX_CONCURRENT_ANALYSES]
            .to_h { |key| [key, ''] }
    output, status = boot(blank)

    assert_predicate status, :success?, output
    assert_includes output, '{"owner":false,"login_enabled":false,"analysis":false}'
  end

  def test_a_malformed_password_hash_still_fails_loudly
    output, status = boot('OWNER_PASSWORD_HASH' => 'hunter2')

    refute_predicate status, :success?
    assert_match(%r{OWNER_PASSWORD_HASH must be generated with bin/owner-password}, output)
  end
end
