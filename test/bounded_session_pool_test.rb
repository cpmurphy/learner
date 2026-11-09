# frozen_string_literal: true

require_relative 'test_helper'
require 'rack'
require 'rack/mock'
require_relative '../lib/bounded_session_pool'

class BoundedSessionPoolTest < Minitest::Test
  # /read only reads the session; /write stores a value; /renew renews the id.
  APP = lambda do |env|
    request = Rack::Request.new(env)
    case request.path
    when '/write' then request.session['value'] = request.params['v']
    when '/renew' then env['rack.session.options'][:renew] = true
    else request.session['value']
    end
    [200, {}, [request.session['value'].to_s]]
  end

  def setup
    @now = 0.0
    @pool = BoundedSessionPool.new(APP, max_sessions: 3, idle_ttl: 60, clock: -> { @now })
    @requests = Rack::MockRequest.new(@pool)
  end

  def cookie(response)
    response['set-cookie']&.split(';')&.first
  end

  def get(path, cookie = nil)
    @requests.get(path, 'HTTP_COOKIE' => cookie)
  end

  def test_requests_that_store_nothing_keep_nothing
    20.times { get('/read') }
    20.times { |i| get('/read', "rack.session=forged-or-expired-#{i}") }

    assert_equal 0, @pool.size
  end

  def test_sessions_with_data_are_kept_and_found_again
    jar = cookie(get('/write?v=hello'))

    assert_equal 'hello', get('/read', jar).body
    assert_equal 1, @pool.size
  end

  def test_least_recently_used_sessions_are_evicted
    jars = %w[a b c].map { |v| cookie(get("/write?v=#{v}")) }
    get('/read', jars[0]) # a is now the most recently used
    get('/write?v=d')

    assert_equal 3, @pool.size
    assert_equal '', get('/read', jars[1]).body, 'b was the least recently used'
    assert_equal 'a', get('/read', jars[0]).body
  end

  def test_idle_sessions_expire
    jar = cookie(get('/write?v=old'))
    @now += 61

    assert_equal '', get('/read', jar).body
    assert_equal 0, @pool.size
  end

  def test_renewing_does_not_leak_entries
    jar = cookie(get('/write?v=x'))
    renewed = cookie(get('/renew', jar))

    refute_equal jar, renewed
    assert_equal 1, @pool.size
    assert_equal 'x', get('/read', renewed).body
  end
end
