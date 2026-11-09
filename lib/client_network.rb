# frozen_string_literal: true

require 'ipaddr'

# How the app identifies a client on the network: which proxies may tell us the
# real client address (X-Forwarded-For), and how addresses are grouped into a
# key for rate limits and engine quotas.
module ClientNetwork
  # Only proxies listed here are believed when they send X-Forwarded-For.
  # Rack's own default trusts every private address, which would let anything
  # that reaches the app from a private network choose its own client IP.
  DEFAULT_TRUSTED_PROXIES = '127.0.0.1/8,::1'

  module_function

  # @param value [String, nil] comma-separated addresses or CIDR ranges
  # @return [Array<IPAddr>]
  def parse_proxies(value)
    entries = value.to_s.split(',').map(&:strip).reject(&:empty?)
    entries = DEFAULT_TRUSTED_PROXIES.split(',') if entries.empty?
    entries.map { |entry| IPAddr.new(entry) }
  rescue IPAddr::Error => e
    raise ArgumentError, "Invalid TRUSTED_PROXIES entry: #{e.message}"
  end

  # Makes Rack::Request#ip believe X-Forwarded-For only from +proxies+.
  def install(proxies)
    Rack::Request.ip_filter = ->(ip) { trusted?(ip, proxies) }
  end

  def trusted?(ip, proxies)
    address = IPAddr.new(ip.to_s).native
    proxies.any? { |network| network.include?(address) }
  rescue IPAddr::Error
    false
  end

  # Groups addresses that belong to one client: IPv6 clients by their /64
  # (they can rotate freely within it), IPv4 by the full address. IPv4-mapped
  # IPv6 addresses count as the plain IPv4 address.
  def key(ip)
    address = IPAddr.new(ip.to_s).native
    address.ipv6? ? "#{address.mask(64)}/64" : address.to_s
  rescue IPAddr::Error
    ip.to_s
  end
end
