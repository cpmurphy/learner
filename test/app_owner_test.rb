# frozen_string_literal: true

require_relative 'test_helper'
require 'rack/test'
require 'json'
require 'tmpdir'
require_relative '../app'

# Owner-only writes and the owner login.
class AppOwnerTest < Minitest::Test
  include Rack::Test::Methods

  PASSWORD = 'correct horse battery staple'
  HASH = OwnerPassword.create(PASSWORD, cost: 2**10)
  OWNER_ROUTES = LearnerApp::OWNER_ROUTES

  def self.app_class(**settings)
    Class.new(LearnerApp) { settings.each { |key, value| set key, value } }
  end

  WITH_LOGIN = app_class(owner_password_hash: HASH)
  PRODUCTION_WITHOUT_LOGIN = app_class(owner_password_hash: nil, environment: :production)
  PRODUCTION_OPEN = app_class(owner_password_hash: nil, environment: :production, owner_access_open: true)
  PRODUCTION_OPEN_WITH_LOGIN = app_class(owner_password_hash: HASH, environment: :production, owner_access_open: true)
  WITH_LOGIN_AND_PROTECTION = app_class(owner_password_hash: HASH, protection: true)

  def setup
    @dir = Dir.mktmpdir('owner-test')
    FileUtils.cp(File.expand_path('data/cagnus-marlsen-with-alt-line.pgn', __dir__), @dir)
    @app_class = WITH_LOGIN
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def app
    @app ||= @app_class.new(pgn_dir: @dir)
  end

  def session_info
    get '/api/session'
    JSON.parse(last_response.body)
  end

  def log_in(password = PASSWORD, env = {})
    post '/login', { password: password }, env
  end

  def test_visitors_cannot_write
    OWNER_ROUTES.each do |path|
      post path, '{}', 'CONTENT_TYPE' => 'application/json'

      assert_equal 403, last_response.status, path
    end
    assert_equal({ 'owner' => false, 'login_enabled' => true }, session_info)
  end

  def test_wrong_password_is_refused
    log_in('guess')

    assert_equal 303, last_response.status
    assert_match(%r{/login\.html\?error=1\z}, last_response.location)
    refute session_info['owner']
  end

  def test_owner_logs_in_with_a_new_session_and_can_write
    get '/api/session'
    before = rack_mock_session.cookie_jar['rack.session']
    log_in

    assert_equal 303, last_response.status
    refute_equal before, rack_mock_session.cookie_jar['rack.session'], 'session id must change at login'
    assert session_info['owner']
    post '/game/save'

    assert_equal 404, last_response.status, 'past the owner check (no game loaded)'
  end

  def test_logout
    log_in
    post '/logout'

    refute session_info['owner']
    post '/game/save'

    assert_equal 403, last_response.status
  end

  def test_production_without_a_password_allows_no_writes
    @app_class = PRODUCTION_WITHOUT_LOGIN
    log_in

    assert_equal({ 'owner' => false, 'login_enabled' => false }, session_info)
    post '/game/save'

    assert_equal 403, last_response.status
  end

  def test_open_owner_access_keeps_single_user_mode_in_production
    @app_class = PRODUCTION_OPEN

    assert_equal({ 'owner' => true, 'login_enabled' => false }, session_info)
  end

  def test_a_password_overrides_open_owner_access
    @app_class = PRODUCTION_OPEN_WITH_LOGIN

    assert_equal({ 'owner' => false, 'login_enabled' => true }, session_info)
  end

  def test_development_without_a_password_keeps_single_user_mode
    @app_class = LearnerApp

    assert_equal({ 'owner' => true, 'login_enabled' => false }, session_info)
  end

  def test_cross_site_post_loses_the_owner_session_behind_caddy
    @app_class = WITH_LOGIN_AND_PROTECTION
    caddy = { 'HTTP_HOST' => 'chess.example.com', 'HTTP_X_FORWARDED_PROTO' => 'https' }
    log_in(PASSWORD, caddy.merge('HTTP_ORIGIN' => 'https://chess.example.com'))
    post '/game/save', '', caddy.merge('HTTP_ORIGIN' => 'https://chess.example.com')

    assert_equal 404, last_response.status, 'same-origin request through the proxy keeps the session'
    post '/game/save', '', caddy.merge('HTTP_ORIGIN' => 'https://evil.example')

    assert_equal 403, last_response.status, 'cross-site request must not act as the owner'
  end

  def test_session_cookie_is_same_site_lax_and_http_only
    log_in
    cookie = last_response.headers['set-cookie'].to_s.downcase

    assert_includes cookie, 'samesite=lax'
    assert_includes cookie, 'httponly'
  end
end
