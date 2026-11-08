# frozen_string_literal: true

require_relative 'test_helper'
require 'rack/test'
require 'json'
require_relative '../app'

# The move-validation endpoint when the engine service is at capacity, and the
# quota subject it sends.
class AppEngineBusyTest < Minitest::Test
  include Rack::Test::Methods

  START_FEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'

  class BusyAnalyzer
    def good_enough_move?(*)
      raise Analyzer::BusyError.new('busy', retry_after: 12)
    end

    def close; end
  end

  def app
    @app ||= LearnerApp.new(pgn_dir: File.expand_path('data', __dir__))
  end

  def setup
    get '/api/pgn_files'
    file = JSON.parse(last_response.body).find { |f| f['name'].include?('cagnus-marlsen-with-alt-line') }
    post '/api/load_game', { pgn_file_id: file['id'] }.to_json, 'CONTENT_TYPE' => 'application/json'
    raise "could not load test game: #{last_response.body}" unless last_response.ok?
  end

  def validate(env = {})
    options = nil
    factory = lambda do |opts = {}|
      options = opts
      BusyAnalyzer.new
    end
    Analyzer.stub :new, factory do
      post '/game/validate_critical_move', { fen: START_FEN, user_move_uci: 'e2e4', good_move_uci: 'd2d4' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }.merge(env)
    end
    options
  end

  def test_busy_engine_returns_429_with_retry_after
    validate

    assert_equal 429, last_response.status
    assert_equal '12', last_response.headers['Retry-After']
    assert_match(/busy/, JSON.parse(last_response.body)['error'])
  end

  def test_subject_is_a_stable_hash_of_the_client_ip
    first = validate('REMOTE_ADDR' => '203.0.113.7')[:subject]
    again = validate('REMOTE_ADDR' => '203.0.113.7')[:subject]
    other = validate('REMOTE_ADDR' => '198.51.100.2')[:subject]

    assert_match(/\A\h{32}\z/, first)
    assert_equal first, again
    refute_equal first, other
    refute_equal '203.0.113.7', first
  end
end
