# frozen_string_literal: true

require_relative 'test_helper'
require 'rack/test'
require 'json'
require_relative '../app'

# Endpoints that use the engine when the engine service is at capacity, and
# the quota subject they send.
class AppEngineBusyTest < Minitest::Test
  include Rack::Test::Methods

  START_FEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'

  class BusyAnalyzer
    %i[good_enough_move? evaluate_best_move evaluate_move best_moves].each do |name|
      define_method(name) { |*| raise Analyzer::BusyError.new('busy', retry_after: 12) }
    end

    def close; end
  end

  UNANNOTATED_FILE = 'quill-2025-08-06' # no $201, so loading it runs whole-game analysis

  def app
    @app ||= LearnerApp.new(pgn_dir: File.expand_path('data', __dir__))
  end

  def setup
    load_file('cagnus-marlsen-with-alt-line')
    raise "could not load test game: #{last_response.body}" unless last_response.ok?
  end

  def file_id(name)
    get '/api/pgn_files'
    JSON.parse(last_response.body).find { |f| f['name'].include?(name) }.fetch('id')
  end

  def load_file(name, env = {})
    id = file_id(name)
    post '/api/load_game', { pgn_file_id: id }.to_json, { 'CONTENT_TYPE' => 'application/json' }.merge(env)
  end

  # Runs the block with Analyzer.new returning a BusyAnalyzer; returns the
  # options of the last Analyzer created.
  def with_busy_engine(&block)
    options = nil
    factory = lambda do |opts = {}|
      options = opts
      BusyAnalyzer.new
    end
    Analyzer.stub(:new, factory, &block)
    options
  end

  def validate(env = {})
    with_busy_engine do
      post '/game/validate_critical_move', { fen: START_FEN, user_move_uci: 'e2e4', good_move_uci: 'd2d4' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }.merge(env)
    end
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

  def test_ipv6_clients_are_keyed_by_their_slash_64
    first = validate('REMOTE_ADDR' => '2001:db8:1:2::1')[:subject]
    same_network = validate('REMOTE_ADDR' => '2001:db8:1:2:aaaa:bbbb:cccc:dddd')[:subject]
    other_network = validate('REMOTE_ADDR' => '2001:db8:1:3::1')[:subject]

    assert_equal first, same_network
    refute_equal first, other_network
  end

  def test_mapped_ipv4_address_matches_the_plain_address
    assert_equal validate('REMOTE_ADDR' => '203.0.113.7')[:subject],
                 validate('REMOTE_ADDR' => '::ffff:203.0.113.7')[:subject]
  end

  def test_busy_during_game_load_returns_429_and_keeps_the_current_game
    get '/game/current_fen'
    before = JSON.parse(last_response.body)
    with_busy_engine { load_file(UNANNOTATED_FILE) }

    assert_equal 429, last_response.status
    assert_equal '12', last_response.headers['Retry-After']
    get '/game/current_fen'

    assert_equal before, JSON.parse(last_response.body)
  end

  def test_whole_game_analysis_is_charged_to_the_visitor
    validate_subject = validate('REMOTE_ADDR' => '203.0.113.7')[:subject]
    options = with_busy_engine { load_file(UNANNOTATED_FILE, 'REMOTE_ADDR' => '203.0.113.7') }

    assert_equal :batch, options[:lane]
    assert_equal validate_subject, options[:subject]
  end

  def test_busy_during_upload_analysis_returns_429_and_saves_nothing
    pgn = File.read(File.expand_path("data/#{UNANNOTATED_FILE}.pgn", __dir__))
    files_before = Dir.children(File.expand_path('data', __dir__)).sort
    options = with_busy_engine do
      post '/api/analyze_and_save', { pgn_content: pgn, filename: 'busy.pgn' }.to_json,
           'CONTENT_TYPE' => 'application/json'
    end

    assert_equal 429, last_response.status
    assert_match(/\A\h{32}\z/, options[:subject])
    assert_equal files_before, Dir.children(File.expand_path('data', __dir__)).sort
  end
end
