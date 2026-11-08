# frozen_string_literal: true

require_relative 'test_helper'
require 'rack/test'
require 'json'
require_relative '../app'

# Ensures untrusted input to the move-validation endpoint never reaches the engine.
class AppValidateMoveInputTest < Minitest::Test
  include Rack::Test::Methods

  START_FEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'

  def app
    @app ||= LearnerApp.new(pgn_dir: File.expand_path('data', __dir__))
  end

  def setup
    get '/api/pgn_files'
    file = JSON.parse(last_response.body).find { |f| f['name'].include?('cagnus-marlsen-with-alt-line') }
    post '/api/load_game', { pgn_file_id: file['id'] }.to_json, 'CONTENT_TYPE' => 'application/json'
    raise "could not load test game: #{last_response.body}" unless last_response.ok?
  end

  def test_rejects_fen_with_injected_command
    post_validate(fen: "#{START_FEN}\nsetoption name Threads value 1024", user_move_uci: 'e2e4', good_move_uci: 'd2d4')

    assert_equal 400, last_response.status
    assert_equal 'Invalid fen or move format', JSON.parse(last_response.body)['error']
  end

  def test_rejects_move_with_injected_command
    post_validate(fen: START_FEN, user_move_uci: "e2e4\nquit", good_move_uci: 'd2d4')

    assert_equal 400, last_response.status
  end

  def test_rejects_non_string_input
    post_validate(fen: START_FEN, user_move_uci: ['e2e4'], good_move_uci: 'd2d4')

    assert_equal 400, last_response.status
  end

  private

  def post_validate(body)
    Analyzer.stub :new, ->(*) { flunk 'engine must not be started for invalid input' } do
      post '/game/validate_critical_move', body.to_json, 'CONTENT_TYPE' => 'application/json'
    end
  end
end
