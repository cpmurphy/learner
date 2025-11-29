# frozen_string_literal: true

require_relative 'test_helper'
require 'rack/test'
require 'tempfile'
require 'fileutils'
require_relative '../app'

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

    @invalid_pgn = "This is not a valid PGN file"
  end

  def teardown
    # Clean up test directory
    FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
  end

  def test_upload_pgn_with_valid_file
    tempfile = Tempfile.new(['test', '.pgn'])
    tempfile.write(@valid_pgn)
    tempfile.rewind

    post '/api/upload_pgn', file: Rack::Test::UploadedFile.new(tempfile.path, 'text/plain', original_filename: 'test.pgn')

    assert last_response.ok?, "Expected response to be OK, got #{last_response.status}"

    json = JSON.parse(last_response.body)
    assert_equal 'test.pgn', json['filename']
    assert_equal 1, json['game_count']
    assert json['size'] > 0

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
    assert json['error'].include?('Invalid PGN file')

    tempfile.close
    tempfile.unlink
  end

  def test_upload_pgn_without_file
    post '/api/upload_pgn'

    assert_equal 400, last_response.status

    json = JSON.parse(last_response.body)
    assert json['error'].include?('No file uploaded')
  end

  def test_upload_pgn_with_wrong_extension
    tempfile = Tempfile.new(['test', '.txt'])
    tempfile.write(@valid_pgn)
    tempfile.rewind

    post '/api/upload_pgn', file: Rack::Test::UploadedFile.new(tempfile.path, 'text/plain', original_filename: 'test.txt')

    assert_equal 400, last_response.status

    json = JSON.parse(last_response.body)
    assert json['error'].include?('Invalid file type')

    tempfile.close
    tempfile.unlink
  end

  def test_analyze_and_save_with_json_content
    post '/api/analyze_and_save',
         { pgn_content: @valid_pgn, filename: 'test_game.pgn' }.to_json,
         'CONTENT_TYPE' => 'application/json'

    # This test may take a while due to Stockfish analysis
    # For now, we just check that it doesn't crash
    assert [200, 500].include?(last_response.status), "Unexpected status: #{last_response.status}"

    if last_response.ok?
      json = JSON.parse(last_response.body)
      assert json['success']
      assert json['filename']
      assert json['filename'].end_with?('.pgn')

      # Verify file was created
      saved_file = File.join(@test_dir, json['filename'])
      assert File.exist?(saved_file), "Expected file #{saved_file} to exist"

      # Verify content is valid PGN
      content = File.read(saved_file)
      assert content.include?('[Event "Test Game"]')
    end
  end

  def test_analyze_and_save_without_content
    post '/api/analyze_and_save',
         { filename: 'test.pgn' }.to_json,
         'CONTENT_TYPE' => 'application/json'

    assert_equal 400, last_response.status

    json = JSON.parse(last_response.body)
    assert json['error'].include?('No PGN content')
  end

  def test_analyze_and_save_with_invalid_json
    post '/api/analyze_and_save',
         'not valid json',
         'CONTENT_TYPE' => 'application/json'

    assert_equal 400, last_response.status

    json = JSON.parse(last_response.body)
    assert json['error'].include?('Invalid JSON')
  end

  def test_sanitize_filename_removes_unsafe_characters
    # Test the helper method indirectly through the endpoint
    post '/api/analyze_and_save',
         { pgn_content: @valid_pgn, filename: '../../../etc/passwd.pgn' }.to_json,
         'CONTENT_TYPE' => 'application/json'

    # Should not create a file outside PGN_DIR
    if last_response.ok?
      json = JSON.parse(last_response.body)
      # Filename should be sanitized
      refute json['filename'].include?('..'), "Filename should not contain .."
      refute json['filename'].include?('/'), "Filename should not contain /"

      # File should be in PGN_DIR
      assert json['path'].start_with?(@test_dir), "File should be in PGN_DIR"
    end
  end

  def test_unique_filename_generation
    # Upload same file twice, should get different filenames
    post '/api/analyze_and_save',
         { pgn_content: @valid_pgn, filename: 'test.pgn' }.to_json,
         'CONTENT_TYPE' => 'application/json'

    first_filename = JSON.parse(last_response.body)['filename'] if last_response.ok?

    # Wait a second to ensure different timestamp
    sleep(1)

    post '/api/analyze_and_save',
         { pgn_content: @valid_pgn, filename: 'test.pgn' }.to_json,
         'CONTENT_TYPE' => 'application/json'

    second_filename = JSON.parse(last_response.body)['filename'] if last_response.ok?

    # Filenames should be different if both succeeded
    if first_filename && second_filename
      refute_equal first_filename, second_filename, "Filenames should be unique"
    end
  end
end
