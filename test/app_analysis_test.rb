# frozen_string_literal: true

require_relative 'test_helper'
require 'rack/test'
require 'json'
require 'tmpdir'
require_relative '../app'
require_relative 'support/stub_analyzer'

# Anonymous visitors on a production site: they may analyze a game of their
# own, which stays in their session, but never see or change the library.
class AppAnalysisTest < Minitest::Test
  include Rack::Test::Methods

  PRODUCTION = Class.new(LearnerApp) do
    set :owner_password_hash, nil
    set :owner_access_open, false
    set :environment, :production
  end

  LIBRARY_FILE = 'cagnus-marlsen-with-alt-line.pgn'

  GAME = <<~PGN
    [Event "Casual"]
    [White "Alice"]
    [Black "Bob"]
    [Result "*"]

    1. e4 e5 2. Nf3 Nc6 3. Bc4 Nf6 *
  PGN

  def setup
    @dir = Dir.mktmpdir('analysis-test')
    FileUtils.cp(File.expand_path("data/#{LIBRARY_FILE}", __dir__), @dir)
    @app_class = PRODUCTION
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def app
    @app ||= @app_class.new(pgn_dir: @dir)
  end

  def analyze(pgn = GAME)
    Analyzer.stub :new, StubAnalyzer.new do
      post '/api/analyze', { pgn_content: pgn }.to_json, 'CONTENT_TYPE' => 'application/json'
    end
    last_response
  end

  def body
    JSON.parse(last_response.body)
  end

  def library_id
    Digest::MD5.hexdigest(File.expand_path(File.join(@dir, LIBRARY_FILE)))
  end

  # Finds one blunder: 2. Nf3 (g1f3) loses 300 centipawns against 2. Nc3.
  class OneBlunderAnalyzer
    def evaluate_best_move(_fen)
      { score: 0, move: 'b1c3', variation: [] }
    end

    def evaluate_move(_fen, move)
      { score: move == 'g1f3' ? 300 : 0 }
    end

    def close; end
  end

  def analyze_with_one_blunder(pgn = GAME)
    Analyzer.stub :new, OneBlunderAnalyzer.new do
      post '/api/analyze', { pgn_content: pgn }.to_json, 'CONTENT_TYPE' => 'application/json'
    end
    last_response
  end

  def test_a_visitor_is_offered_a_better_move_at_a_blunder
    assert_equal 200, analyze_with_one_blunder.status, last_response.body
    get '/api/analysis'

    assert body['has_initial_critical_moment_for_white']
    check_better_move_offered_after_knight_move
  end

  def test_the_owner_is_offered_a_better_move_in_an_unannotated_library_game
    @app_class = LearnerApp # development: everyone is the owner
    File.write(File.join(@dir, 'fresh.pgn'), GAME)
    Analyzer.stub :new, OneBlunderAnalyzer.new do
      post '/api/load_game', { pgn_file_id: Digest::MD5.hexdigest(File.join(@dir, 'fresh.pgn')) }.to_json,
           'CONTENT_TYPE' => 'application/json'
    end

    assert_equal 200, last_response.status, last_response.body
    check_better_move_offered_after_knight_move
  end

  def test_visitors_cannot_list_or_open_library_games
    get '/api/pgn_files'

    assert_equal 403, last_response.status
    post '/api/load_game', { pgn_file_id: library_id }.to_json, 'CONTENT_TYPE' => 'application/json'

    assert_equal 403, last_response.status
  end

  def test_visitor_analyzes_a_game_without_anything_being_written
    before = Dir.children(@dir).sort

    assert_equal 200, analyze.status, last_response.body
    assert_equal '/game?id=analysis', body['game_url']
    assert_equal before, Dir.children(@dir).sort, 'nothing may be written to the library'
  end

  def test_visitor_plays_through_their_analysis
    analyze
    get '/api/session'

    assert body['analysis']
    get '/api/analysis'

    assert_equal [%w[Alice Bob], 7], [body.values_at('white_player', 'black_player'), body['total_positions']]
    post '/game/next_move'

    assert_equal 1, body['move_index']
  end

  def test_an_analysis_is_visible_only_in_its_own_session
    analyze
    clear_cookies
    get '/api/analysis'

    assert_equal 404, last_response.status
    get '/api/session'

    refute body['analysis']
  end

  def test_visitors_cannot_save_an_analysis
    analyze
    post '/game/save'

    assert_equal 403, last_response.status
  end

  def test_opening_a_library_game_replaces_the_analysis
    @app_class = LearnerApp # development: everyone is the owner
    analyze
    post '/api/load_game', { pgn_file_id: library_id }.to_json, 'CONTENT_TYPE' => 'application/json'

    assert_equal 200, last_response.status, last_response.body
    get '/api/analysis'

    assert_equal 404, last_response.status
  end

  def test_rejects_an_illegal_game
    assert_equal 400, analyze("[Result \"*\"]\n\n1. e4 e5 2. Ke3 *\n").status
    assert_match(/2\. Ke3 is not legal/, body['error'])
  end

  def test_rejects_a_game_from_a_set_up_position
    analyze("[FEN \"4k3/8/8/8/8/8/8/4K3 w - - 0 1\"]\n[SetUp \"1\"]\n[Result \"*\"]\n\n1. Kd2 *\n")

    assert_equal 400, last_response.status
    assert_match(/standard starting position/, body['error'])
  end

  def test_rejects_unreadable_empty_and_moveless_input
    assert_equal 400, analyze('this is not chess').status
    assert_match(/Could not read the PGN/, body['error'])
    assert_equal 400, analyze('   ').status
    assert_equal 400, analyze("[White \"A\"]\n[Result \"*\"]\n\n*\n").status
  end

  def test_rejects_a_game_that_is_too_long
    moves = Array.new((LearnerApp::MAX_ANALYSIS_PLIES / 4) + 1) { 'Nf3 Nf6 Ng1 Ng8' }.join(' ')

    assert_equal 400, analyze("[Result \"*\"]\n\n#{moves} *\n").status
    assert_match(/too long/, body['error'])
  end

  def test_rejects_a_body_that_is_too_large
    huge = "[Result \"*\"]\n\n1. e4 {#{'x' * LearnerApp::MAX_ANALYSIS_PGN_BYTES}} *"

    assert_equal 413, analyze(huge).status
  end

  def test_requires_json
    post '/api/analyze', pgn_content: GAME

    assert_equal 415, last_response.status
  end

  def test_refuses_when_every_analysis_slot_is_taken
    LearnerApp::ANALYSIS_SLOTS.stub :run, [false, nil] do
      analyze
    end

    assert_equal 429, last_response.status
    assert_equal '30', last_response.headers['retry-after']
    get '/api/analysis'

    assert_equal 404, last_response.status, 'a refused analysis leaves nothing behind'
  end

  def test_analysis_counts_against_the_hourly_upload_limit
    Rack::Attack.reset!
    Rack::Attack.enabled = true
    limit = RateLimits::RULES['uploads'].first
    statuses = Array.new(limit + 1) { analyze('not chess').status }

    assert_equal [400] * limit, statuses.first(limit)
    assert_equal 429, statuses.last
  ensure
    Rack::Attack.enabled = false
    Rack::Attack.reset!
  end

  private

  # What the game page needs to offer "Try a better move" after 2. Nf3.
  def check_better_move_offered_after_knight_move
    post '/game/next_critical_moment', { learning_side: 'white' }.to_json, 'CONTENT_TYPE' => 'application/json'

    assert_equal 3, body['move_index'], last_response.body
    last_move = body['last_move']

    assert_equal %w[Nf3 white], last_move.values_at('san', 'turn')
    assert last_move['is_critical'], 'the blunder itself must be the critical move'
    assert_equal 'Nc3', last_move['good_move_san']
  end
end
