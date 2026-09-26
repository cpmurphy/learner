# frozen_string_literal: true

require_relative '../test_helper'
require 'rack/test'
require 'fileutils'
require 'pgn'
require_relative '../../app'

class AppGameEndpointsTest < Minitest::Test
  include Rack::Test::Methods

  def app
    LearnerApp
  end

  def setup
    @test_dir = 'test/data'
    ENV['PGN_DIR'] = @test_dir

    @threadwell_pgn_file = File.join(@test_dir, 'threadwell-2025-05-26-01.pgn')
    @threadwell_pgn_content = File.read(@threadwell_pgn_file)

    # Create a test game object (need to dup the string because it's frozen)
    games = PGN.parse(@threadwell_pgn_content.dup)
    @threadwell_game = games.first
  end

  def teardown; end

  # rubocop:disable-next Minitest/MultipleAssertions
  def test_load_game_in_session
    get '/api/pgn_files'

    assert_predicate last_response, :ok?, "Failed to get PGN files: #{last_response.body}"

    files = JSON.parse(last_response.body)

    assert_equal 5, files.length
    threadwell_file = files.find { |f| f['name'] == 'threadwell-2025-05-26-01.pgn' }

    assert threadwell_file
    assert_equal 'Player', threadwell_file['white']
    assert_equal 'Femi Threadwell', threadwell_file['black']
    threadwell_id = threadwell_file['id']

    post '/api/load_game', { pgn_file_id: threadwell_id }.to_json,
         'CONTENT_TYPE' => 'application/json'

    assert_predicate last_response, :ok?, "Failed to load game: #{last_response.body}"
    game_state = JSON.parse(last_response.body)

    assert_equal 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', game_state['fen']
    assert_equal 0, game_state['move_index']
    assert_equal 118, game_state['total_positions']
    assert_nil game_state['last_move']

    post '/game/next_move'

    assert_predicate last_response, :ok?, "Failed navigate to next move: #{last_response.body}"
    game_state = JSON.parse(last_response.body)

    assert_equal 1, game_state['move_index']
    assert_equal 'e4', game_state['last_move']['san']
    assert_equal 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', game_state['last_move']['fen_before_move']

    post '/game/next_critical_moment', { learning_side: 'white' }.to_json,
         'CONTENT_TYPE' => 'application/json'

    assert_predicate last_response, :ok?, "Failed navigate to next move: #{last_response.body}"
    game_state = JSON.parse(last_response.body)

    assert_equal 23, game_state['move_index']
    last_move = game_state['last_move']

    assert_equal 12, last_move['number']
    assert last_move['is_critical']
    assert_equal 'Ng5', last_move['san']
    assert_equal 'Bg5', last_move['good_move_san']
    assert_equal 'r1bq1k1r/pppp1Bpp/2n5/8/3P4/1Q3N2/P4PPP/b1B2RK1 w - - 1 12', last_move['fen_before_move']

    post '/game/validate_critical_move', { fen:	'r1bq1k1r/pppp1Bpp/2n5/8/3P4/1Q3N2/P4PPP/b1B2RK1 w - - 1 12',
                                           good_move_uci:	'c1g5',
                                           user_move_uci:	'c1g5' }.to_json,
         'CONTENT_TYPE' => 'application/json'

    assert_predicate last_response, :ok?, "Failed validate guess: #{last_response.body}"
    validation_response = JSON.parse(last_response.body)

    assert validation_response['good_enough']
    assert_equal 8, validation_response['variation_sans'].length

    post '/game/validate_critical_move', { fen:	'r1b2k1r/ppppqBpp/2n5/6N1/3P4/1Q6/P4PPP/b1B2RK1 w - - 3 13',
                                           good_move_uci:	'b3d1',
                                           user_move_uci:	'c1f4' }.to_json,
         'CONTENT_TYPE' => 'application/json'

    assert_predicate last_response, :ok?, "Failed validate bad guess: #{last_response.body}"
    validation_response = JSON.parse(last_response.body)

    refute validation_response['good_enough']

    post '/game/go_to_end'

    assert_predicate last_response, :ok?, "Failed navigate to end: #{last_response.body}"
    game_state = JSON.parse(last_response.body)

    assert_equal 117, game_state['move_index']
    assert_equal '8/6k1/5bp1/7p/5P1P/5KP1/2Q5/8 b - - 0 59', game_state['fen']
    last_move = game_state['last_move']

    assert_equal 59, last_move['number']
    refute last_move['is_critical']
    assert_equal 'Qxc2', last_move['san']
    assert_equal '8/6k1/5bp1/7p/5P1P/1Q3KP1/2r5/8 w - - 5 59', last_move['fen_before_move']

    post '/game/prev_move'

    assert_predicate last_response, :ok?, "Failed navigate to previous move: #{last_response.body}"
    game_state = JSON.parse(last_response.body)

    assert_equal 116, game_state['move_index']
    assert_equal '8/6k1/5bp1/7p/5P1P/1Q3KP1/2r5/8 w - - 5 59', game_state['fen']
    last_move = game_state['last_move']

    assert_equal 58, last_move['number']
    refute last_move['is_critical']
    assert_equal 'Kg7', last_move['san']
    assert_equal '8/5k2/5bp1/7p/5P1P/1Q3KP1/2r5/8 b - - 4 58', last_move['fen_before_move']

    post '/game/go_to_start'

    assert_predicate last_response, :ok?, "Failed navigate to start: #{last_response.body}"
    game_state = JSON.parse(last_response.body)

    assert_equal 0, game_state['move_index']
    assert_nil game_state['last_move']
    assert_equal 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', game_state['fen']
  end
end
