# frozen_string_literal: true

require 'json'
require 'rack/attack'
require_relative 'client_network'
require_relative 'memory_rate_store'

# Per-client rate limits for the public site (Rack::Attack). Clients are keyed
# with ClientNetwork.key, so an IPv6 client is one client across its /64.
#
# The engine service has its own per-visitor quota and global budget; these
# limits stop cheap floods (and password guessing) before they reach Ruby code
# that does real work.
module RateLimits
  STATIC_PREFIXES = %w[/scripts/ /styles/ /3rdparty-assets/ /favicon].freeze

  # name => [limit, period in seconds, matcher]
  RULES = {
    'requests' => [600, 300, ->(req) { !static?(req) }],
    'validate-move' => [30, 60, ->(req) { req.post? && req.path == '/game/validate_critical_move' }],
    'validate-move-hourly' => [300, 3600, ->(req) { req.post? && req.path == '/game/validate_critical_move' }],
    'load-game' => [20, 60, ->(req) { req.post? && req.path == '/api/load_game' }],
    'login' => [5, 60, ->(req) { req.post? && req.path == '/login' }],
    'login-hourly' => [20, 3600, ->(req) { req.post? && req.path == '/login' }],
    # Whole-game analysis is the most expensive thing a visitor can ask for.
    'uploads' => [10, 3600, lambda { |req|
      req.post? && %w[/api/analyze /api/upload_pgn /api/analyze_and_save].include?(req.path)
    }]
  }.freeze

  module_function

  def configure(attack = Rack::Attack, store: MemoryRateStore.new)
    attack.cache.store = store
    RULES.each do |name, (limit, period, matcher)|
      attack.throttle(name, limit: limit, period: period) do |req|
        ClientNetwork.key(req.ip) if matcher.call(req)
      end
    end
    attack.throttled_responder = method(:throttled_response)
  end

  def static?(req)
    req.get? && STATIC_PREFIXES.any? { |prefix| req.path.start_with?(prefix) }
  end

  def throttled_response(request)
    match = request.env['rack.attack.match_data'] || {}
    period = match[:period].to_i
    retry_after = period.positive? ? period - (match[:epoch_time].to_i % period) : 60
    body = { error: 'Too many requests. Please slow down and try again shortly.' }.to_json
    [429, { 'content-type' => 'application/json', 'retry-after' => retry_after.to_s }, [body]]
  end
end
