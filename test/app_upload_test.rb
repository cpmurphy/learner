# frozen_string_literal: true

require_relative 'test_helper'
require 'rack/test'
require 'tempfile'
require 'fileutils'
require 'minitest/mock'
require 'pgn'
require_relative '../app'
require_relative '../lib/move_translator'

class AppUploadTest < Minitest::Test
  include Rack::Test::Methods

  def app
    LearnerApp
  end

  def setup
    # Create a temporary directory for testing
    @test_dir = Dir.mktmpdir('pgn_upload_test')
    ENV['PGN_DIR'] = @test_dir

    # Create a valid PGN for testing
    @valid_pgn = <<~PGN
      [Event "Test Game"]
      [Site "Testing"]
      [Date "2025.10.25"]
      [Round "1"]
      [White "Player1"]
      [Black "Player2"]
      [Result "1-0"]

      1.e4 e5 2.Nf3 Nc6 3.Bc4 1-0
    PGN

    @invalid_pgn = 'This is not a valid PGN file'
  end

  def teardown
    # Clean up test directory
    FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
  end

  # Helper method to create a mock analyzer for tests that need to avoid Stockfish
  def with_mock_analyzer(pgn_content = @valid_pgn, &block)
    require_relative '../lib/analyzer'
    mock_analyzer = Minitest::Mock.new

    # Create a simple game to determine how many positions to mock
    games = PGN.parse(pgn_content.dup)
    game = games.first
    translator = MoveTranslator.new

    # Mock analysis for each move position
    (0...game.moves.size).each do |i|
      next unless game.positions[i] && game.moves[i]

      fen = game.positions[i].to_fen.to_s
      # Mock best move analysis - return a good score
      mock_analyzer.expect :evaluate_best_move,
                           { score: 200, move: 'e2e4', variation: %w[e2e4 e7e5] },
                           [fen]

      # Mock played move analysis - return a score that doesn't trigger blunder (to keep test simple)
      translator.load_game_from_fen(fen)
      uci_move = translator.translate_move(game.moves[i].notation)
      mock_analyzer.expect :evaluate_move, { score: 150 }, [fen, uci_move]
    end
    mock_analyzer.expect :close, nil

    Analyzer.stub :new, mock_analyzer, &block

    mock_analyzer.verify
  end

  def test_upload_pgn_with_valid_file
    tempfile = Tempfile.new(['test', '.pgn'])
    tempfile.write(@valid_pgn)
    tempfile.rewind

    post '/api/upload_pgn', file: Rack::Test::UploadedFile.new(tempfile.path, 'text/plain', original_filename: 'test.pgn')

    assert_predicate last_response, :ok?, "Expected response to be OK, got #{last_response.status}"

    json = JSON.parse(last_response.body)

    assert_equal 'test.pgn', json['filename']
    assert_equal 1, json['game_count']
    assert_predicate json['size'], :positive?

    tempfile.close
    tempfile.unlink
  end

  def test_upload_pgn_with_invalid_content
    tempfile = Tempfile.new(['test', '.pgn'])
    tempfile.write(@invalid_pgn)
    tempfile.rewind

    post '/api/upload_pgn', file: Rack::Test::UploadedFile.new(tempfile.path, 'text/plain', original_filename: 'invalid.pgn')

    assert_equal 400, last_response.status

    json = JSON.parse(last_response.body)

    assert_includes json['error'], 'Invalid PGN file'

    tempfile.close
    tempfile.unlink
  end

  def test_upload_pgn_without_file
    post '/api/upload_pgn'

    assert_equal 400, last_response.status

    json = JSON.parse(last_response.body)

    assert_includes json['error'], 'No file uploaded'
  end

  def test_upload_pgn_with_wrong_extension
    tempfile = Tempfile.new(['test', '.txt'])
    tempfile.write(@valid_pgn)
    tempfile.rewind

    post '/api/upload_pgn', file: Rack::Test::UploadedFile.new(tempfile.path, 'text/plain', original_filename: 'test.txt')

    assert_equal 400, last_response.status

    json = JSON.parse(last_response.body)

    assert_includes json['error'], 'Invalid file type'

    tempfile.close
    tempfile.unlink
  end

  def test_analyze_and_save_with_json_content
    with_mock_analyzer do
      post '/api/analyze_and_save',
           { pgn_content: @valid_pgn, filename: 'test_game.pgn' }.to_json,
           'CONTENT_TYPE' => 'application/json'

      assert_predicate last_response, :ok?, "Expected OK, got #{last_response.status}: #{last_response.body}"

      json = JSON.parse(last_response.body)

      assert json['success']
      assert json['filename']
      assert json['filename'].end_with?('.pgn')

      # Verify file was created
      saved_file = File.join(@test_dir, json['filename'])

      assert_path_exists saved_file, "Expected file #{saved_file} to exist"

      # Verify content is valid PGN
      content = File.read(saved_file)

      assert_includes content, '[Event "Test Game"]'
    end
  end

  def test_analyze_and_save_without_content
    post '/api/analyze_and_save',
         { filename: 'test.pgn' }.to_json,
         'CONTENT_TYPE' => 'application/json'

    assert_equal 400, last_response.status

    json = JSON.parse(last_response.body)

    assert_includes json['error'], 'No PGN content'
  end

  def test_analyze_and_save_with_invalid_json
    post '/api/analyze_and_save',
         'not valid json',
         'CONTENT_TYPE' => 'application/json'

    assert_equal 400, last_response.status

    json = JSON.parse(last_response.body)

    assert_includes json['error'], 'Invalid JSON'
  end

  def test_sanitize_filename_removes_unsafe_characters
    # Test the helper method indirectly through the endpoint
    with_mock_analyzer do
      post '/api/analyze_and_save',
           { pgn_content: @valid_pgn, filename: '../../../etc/passwd.pgn' }.to_json,
           'CONTENT_TYPE' => 'application/json'

      assert_predicate last_response, :ok?, "Expected OK, got #{last_response.status}: #{last_response.body}"

      json = JSON.parse(last_response.body)
      # Filename should be sanitized
      refute_includes json['filename'], '..', 'Filename should not contain ..'
      refute_includes json['filename'], '/', 'Filename should not contain /'

      # File should be in PGN_DIR
      assert json['path'].start_with?(@test_dir), 'File should be in PGN_DIR'
    end
  end

  def test_unique_filename_generation
    # Upload same file twice, should get different filenames
    first_filename = nil
    with_mock_analyzer do
      post '/api/analyze_and_save',
           { pgn_content: @valid_pgn, filename: 'test.pgn' }.to_json,
           'CONTENT_TYPE' => 'application/json'

      assert_predicate last_response, :ok?, "First request failed: #{last_response.body}"
      first_filename = JSON.parse(last_response.body)['filename']
    end

    # Wait a second to ensure different timestamp
    sleep(1)

    # Second request with new mock
    with_mock_analyzer do
      post '/api/analyze_and_save',
           { pgn_content: @valid_pgn, filename: 'test.pgn' }.to_json,
           'CONTENT_TYPE' => 'application/json'

      assert_predicate last_response, :ok?, "Second request failed: #{last_response.body}"
      second_filename = JSON.parse(last_response.body)['filename']

      # Filenames should be different
      refute_equal first_filename, second_filename, 'Filenames should be unique'
    end
  end
end
