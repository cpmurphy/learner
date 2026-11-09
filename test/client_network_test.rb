# frozen_string_literal: true

require_relative 'test_helper'
require 'rack'
require_relative '../lib/client_network'

class ClientNetworkTest < Minitest::Test
  def setup
    @original_filter = Rack::Request.ip_filter
  end

  def teardown
    Rack::Request.ip_filter = @original_filter
  end

  def ip_for(remote, forwarded)
    Rack::Request.new(Rack::MockRequest.env_for('/', 'REMOTE_ADDR' => remote, 'HTTP_X_FORWARDED_FOR' => forwarded)).ip
  end

  def test_default_trusts_only_loopback
    proxies = ClientNetwork.parse_proxies(nil)

    assert ClientNetwork.trusted?('127.0.0.1', proxies)
    assert ClientNetwork.trusted?('::1', proxies)
    refute ClientNetwork.trusted?('10.89.0.1', proxies)
    refute ClientNetwork.trusted?('not an ip', proxies)
  end

  def test_forwarded_for_is_believed_only_from_trusted_proxies
    ClientNetwork.install(ClientNetwork.parse_proxies('10.89.10.1'))

    assert_equal '203.0.113.7', ip_for('10.89.10.1', '203.0.113.7')
    assert_equal '10.89.10.2', ip_for('10.89.10.2', '203.0.113.7'), 'untrusted private address may not choose the IP'
    assert_equal '198.51.100.9', ip_for('198.51.100.9', '203.0.113.7')
  end

  def test_cidr_ranges_and_bad_entries
    proxies = ClientNetwork.parse_proxies('10.89.10.0/24, fd00::/8')

    assert ClientNetwork.trusted?('10.89.10.77', proxies)
    assert ClientNetwork.trusted?('fd12::5', proxies)
    assert_raises(ArgumentError) { ClientNetwork.parse_proxies('10.89.10.0/24,nonsense') }
  end

  def test_key_groups_ipv6_by_slash_64
    assert_equal ClientNetwork.key('2001:db8:1:2::1'), ClientNetwork.key('2001:db8:1:2:ffff::9')
    refute_equal ClientNetwork.key('2001:db8:1:2::1'), ClientNetwork.key('2001:db8:1:3::1')
    assert_equal '203.0.113.7', ClientNetwork.key('::ffff:203.0.113.7')
  end
end
