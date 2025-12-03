# frozen_string_literal: true

require 'sinatra'
require 'pgn'
require 'json'
require 'digest'
require_relative 'lib/game_editor'
require_relative 'lib/app_helpers' # Require the new helpers
require_relative 'lib/analyzer'

class LearnerApp < Sinatra::Base
  enable :sessions
  set :session_store, Rack::Session::Pool

  # --- Configuration ---
  configure do
    set :public_folder, File.join(File.dirname(__FILE__), 'public')
    set :bind, '0.0.0.0'
  end

  # Disable Rack::Protection for API endpoints to allow uploads
  configure :development, :test do
    set :protection, false
  end
  # --- End Configuration ---

  # --- Helpers ---
  helpers do
    include AppHelpers # Include methods from AppHelpers module

    def game_loaded?
      !session[:game].nil? && session[:game].respond_to?(:positions) && !session[:game].positions.empty?
    end

    def current_board_fen
      return nil unless game_loaded? && session[:game].positions[session[:current_move_index]]

      session[:game].positions[session[:current_move_index]].to_fen.to_s
    end

    def json_response(data, status_code = 200)
      content_type :json
      status status_code
      data.to_json
    end

    # Ensure the PGN text ends with a valid game termination token.
    # If missing, and a [Result "..."] tag exists, append that token to the end.
    def ensure_pgn_has_result_termination(pgn_text)
      return pgn_text if pgn_text.nil? || pgn_text.strip.empty?

      result_tag = pgn_text[/\[Result\s+"([^"]+)"\]/i, 1]
      return pgn_text unless result_tag

      normalized_result = result_tag.strip
      return pgn_text unless ['1-0', '0-1', '1/2-1/2', '*'].include?(normalized_result)

      trimmed = pgn_text.rstrip
      return pgn_text if trimmed.match?(%r{(1-0|0-1|1/2-1/2|\*)\s*\z})

      "#{trimmed} #{normalized_result}\n"
    end

    # Sanitize filename to prevent path traversal and ensure safe filenames
    def sanitize_filename(filename)
      # Remove path components and keep only the basename
      basename = File.basename(filename)
      # Remove or replace unsafe characters
      basename.gsub(/[^0-9A-Za-z.\-_]/, '_')
    end

    # Generate a unique filename by appending timestamp
    def generate_unique_filename(base_filename)
      ext = File.extname(base_filename)
      name = File.basename(base_filename, ext)
      timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
      "#{name}_#{timestamp}#{ext}"
    end

    # Check if file is within PGN_DIR boundary
    def within_pgn_dir?(file_path)
      pgn_dir = ENV.fetch('PGN_DIR', nil)
      return false if pgn_dir.nil? || pgn_dir.empty?

      abs_file_path = File.expand_path(file_path)
      abs_pgn_dir = File.expand_path(pgn_dir)
      abs_file_path.start_with?(abs_pgn_dir)
    end

    # Generate a stable ID for a file based on its absolute path
    # This ID will remain constant even when new files are added
    def generate_stable_file_id(file_path)
      abs_path = File.expand_path(file_path)
      Digest::MD5.hexdigest(abs_path)
    end
  end
  # --- End Helpers ---

  def initialize
    super
    @available_pgns = [] # Holds {id: string, name: string, path: string} for discovered PGN files
    scan_pgn_directory
  end

  # Scan PGN_DIR and populate @available_pgns
  def scan_pgn_directory
    @available_pgns = []
    pgn_dir_path = ENV.fetch('PGN_DIR', nil)

    return unless pgn_directory_valid?(pgn_dir_path)

    pgn_files = Dir.glob(File.join(pgn_dir_path, '*.pgn'))
    sorted_files = sort_pgn_files_by_mtime(pgn_files)

    if sorted_files.empty?
      puts "No PGN files found in #{pgn_dir_path}."
    else
      process_pgn_files(sorted_files, pgn_dir_path)
    end
  end

  def pgn_directory_valid?(pgn_dir_path)
    if pgn_dir_path.nil? || pgn_dir_path.empty?
      print_pgn_dir_error('PGN_DIR environment variable not set.',
                          'Please provide the path to a directory containing PGN files.',
                          'Example: PGN_DIR=./test/data bundle exec puma config.ru')
      return false
    elsif !Dir.exist?(pgn_dir_path)
      print_pgn_dir_error("PGN directory not found at path: #{pgn_dir_path}",
                          'Please ensure the PGN_DIR environment variable points to an existing directory.')
      return false
    end
    true
  end

  def print_pgn_dir_error(*messages)
    puts '---------------------------------------------------------------------------------------'
    messages.each { |msg| puts "ERROR: #{msg}" }
    puts 'The application will start, but game functionality will be disabled.'
    puts '---------------------------------------------------------------------------------------'
  end

  def sort_pgn_files_by_mtime(pgn_files)
    begin
      pgn_files.sort_by! { |file_path| File.mtime(file_path) }
      pgn_files.reverse!
    rescue StandardError => e
      puts "WARNING: Failed to sort PGN files by modified time: #{e.message}. Falling back to default order."
    end
    pgn_files
  end

  def process_pgn_files(pgn_files, pgn_dir_path)
    pgn_files.each do |file_path|
      process_single_pgn_file(file_path, pgn_dir_path)
    end
  end

  def process_single_pgn_file(file_path, pgn_dir_path)
    filename = File.basename(file_path)
    abs_path = File.expand_path(file_path)

    unless abs_path.start_with?(File.expand_path(pgn_dir_path))
      puts "WARNING: File #{file_path} is outside the PGN_DIR and will be ignored."
      return
    end

    metadata = extract_pgn_file_metadata(abs_path, filename)
    return unless metadata

    stable_id = generate_stable_file_id(abs_path)
    @available_pgns << {
      id: stable_id,
      name: filename,
      path: abs_path,
      game_count: metadata[:game_count],
      white: metadata[:white],
      black: metadata[:black],
      date: metadata[:date]
    }
  end

  def extract_pgn_file_metadata(abs_path, filename)
    game_count = 0
    white_player = nil
    black_player = nil
    date = nil

    begin
      pgn_content = File.read(abs_path)
      pgn_content = ensure_pgn_has_result_termination(pgn_content)
      games_in_file = PGN.parse(pgn_content)
      game_count = games_in_file.size

      if games_in_file.any? && games_in_file.first.tags
        white_player = games_in_file.first.tags['White']
        black_player = games_in_file.first.tags['Black']
        date = games_in_file.first.tags['Date']
      end
    rescue StandardError => e
      puts "WARNING: Could not parse PGN file #{filename} to count games. Error: #{e.message}. Assuming 0 games."
      game_count = 0
    end

    {
      game_count: game_count,
      white: white_player,
      black: black_player,
      date: date
    }
  end

  # --- Routes ---

  # Serve index.html for the root path
  get '/' do
    send_file File.join(settings.public_folder, 'index.html')
  end

  get '/game' do
    send_file File.join(settings.public_folder, 'game.html')
  end

  # API endpoint to list available PGN files
  get '/api/pgn_files' do
    # Always scan to get the latest list of files
    scan_pgn_directory

    # Return id, name, game_count, and header information
    files_for_client = @available_pgns.map do |pgn_meta|
      {
        id: pgn_meta[:id],
        name: pgn_meta[:name],
        game_count: pgn_meta[:game_count],
        white: pgn_meta[:white],
        black: pgn_meta[:black],
        date: pgn_meta[:date]
      }
    end
    json_response(files_for_client)
  end

  # API endpoint to load the first game from a selected PGN file
  post '/api/load_game' do
    scan_pgn_directory
    params = parse_json_body
    return params if params.is_a?(Hash) && params[:error]

    pgn_file_id = params['pgn_file_id']
    return json_response({ error: 'Missing pgn_file_id parameter' }, 400) unless pgn_file_id

    pgn_meta = @available_pgns.find { |p| p[:id] == pgn_file_id }
    return json_response({ error: "PGN file not found for ID: #{pgn_file_id}" }, 404) unless pgn_meta

    load_game_from_pgn_file(pgn_meta)
  end

  def parse_json_body
    JSON.parse(request.body.read)
  rescue JSON::ParserError
    json_response({ error: 'Invalid JSON in request body' }, 400)
  end

  def load_game_from_pgn_file(pgn_meta)
    games_in_file = parse_pgn_file(pgn_meta[:path])
    return handle_empty_pgn_file(pgn_meta) if games_in_file.empty?

    initialize_game_session(games_in_file.first, pgn_meta[:path])
    build_load_game_response(pgn_meta)
  rescue StandardError => e
    handle_pgn_load_error(pgn_meta, e)
  end

  def parse_pgn_file(file_path)
    pgn_content = File.read(file_path)
    pgn_content = ensure_pgn_has_result_termination(pgn_content)
    PGN.parse(pgn_content)
  end

  def handle_empty_pgn_file(pgn_meta)
    clear_game_session
    json_response({ error: "No games found in PGN file: #{pgn_meta[:name]}" }, 400)
  end

  def initialize_game_session(game, file_path)
    session[:game] = game
    session[:pgn_file_path] = file_path
    process_critical_moments_for_game
    session[:current_move_index] = 0
  end

  def clear_game_session
    session[:game] = nil
    session[:current_move_index] = 0
  end

  def handle_pgn_load_error(pgn_meta, error)
    clear_game_session
    puts "ERROR: Could not parse PGN file: #{pgn_meta[:path]}."
    puts "Details: #{error.message}"
    json_response({ error: "Could not parse PGN file: #{pgn_meta[:name]}. Details: #{error.message}" }, 500)
  end

  def process_critical_moments_for_game
    has_critical_moments = session[:game].moves.any? { |m| m.annotation&.include?('$201') }
    game_editor = GameEditor.new

    if has_critical_moments
      game_editor.shift_critical_annotations(session[:game])
    else
      game_editor.add_blunder_annotations(session[:game])
    end
  end

  def build_load_game_response(pgn_meta)
    response_data = build_load_game_response_data(pgn_meta)
    json_response(response_data)
  end

  def build_load_game_response_data(pgn_meta)
    {
      fen: current_board_fen,
      move_index: session[:current_move_index],
      total_positions: session[:game].positions.size,
      last_move: get_last_move_info(session[:game], session[:current_move_index]),
      message: "Successfully loaded game from #{pgn_meta[:name]}",
      has_initial_critical_moment_for_white: initial_critical_moment_for_white?,
      white_player: extract_player_names[:white],
      black_player: extract_player_names[:black]
    }
  end

  def initial_critical_moment_for_white?
    !find_critical_moment_position_index(session[:game].moves, 0, 'white').nil?
  end

  def extract_player_names
    {
      white: session[:game].tags['White'] || 'Unknown White',
      black: session[:game].tags['Black'] || 'Unknown Black'
    }
  end

  # API endpoint to get the current FEN of the loaded game
  get '/game/current_fen' do
    unless game_loaded?
      return json_response({ error: 'No game loaded. Please select a PGN file and load a game.' },
                           404)
    end

    last_move = get_last_move_info(session[:game], session[:current_move_index])
    white_player = session[:game].tags['White'] || 'Unknown White'
    black_player = session[:game].tags['Black'] || 'Unknown Black'
    json_response({
                    fen: current_board_fen,
                    move_index: session[:current_move_index],
                    total_positions: session[:game].positions.size,
                    last_move: last_move,
                    white_player: white_player,
                    black_player: black_player
                  })
  end

  # API endpoint to go to the next move of the loaded game
  post '/game/next_move' do
    unless game_loaded?
      return json_response({ error: 'No game loaded. Please select a PGN file and load a game.' },
                           404)
    end

    if session[:current_move_index] < session[:game].positions.size - 1
      session[:current_move_index] += 1
      last_move = get_last_move_info(session[:game], session[:current_move_index])
      json_response({ fen: current_board_fen, move_index: session[:current_move_index], last_move: last_move })
    else
      last_move = get_last_move_info(session[:game], session[:current_move_index])
      json_response({
                      fen: current_board_fen,
                      move_index: session[:current_move_index],
                      message: 'Already at the last move.',
                      last_move: last_move
                    })
    end
  end

  # API endpoint to go to the previous move of the loaded game
  post '/game/prev_move' do
    unless game_loaded?
      return json_response({ error: 'No game loaded. Please select a PGN file and load a game.' },
                           404)
    end

    if session[:current_move_index].positive?
      session[:current_move_index] -= 1
      last_move = get_last_move_info(session[:game], session[:current_move_index])
      json_response({ fen: current_board_fen, move_index: session[:current_move_index], last_move: last_move })
    else
      last_move = get_last_move_info(session[:game], session[:current_move_index]) # Will be nil for index 0
      json_response({
                      fen: current_board_fen,
                      move_index: session[:current_move_index],
                      message: 'Already at the first move.',
                      last_move: last_move
                    })
    end
  end

  # API endpoint to go to the next critical move for the learning side
  post '/game/next_critical_moment' do
    unless game_loaded?
      return json_response({ error: 'No game loaded. Please select a PGN file and load a game.' }, 404)
    end

    params = parse_json_body
    return params if params.is_a?(Hash) && params[:error]

    learning_side = params['learning_side']
    unless %w[white black].include?(learning_side)
      return json_response({ error: "Invalid learning_side parameter. Must be 'white' or 'black'." }, 400)
    end

    find_and_jump_to_next_critical_moment(learning_side)
  end

  def find_and_jump_to_next_critical_moment(learning_side)
    start_search_from_move_idx = session[:current_move_index]
    new_critical_position_index = find_critical_moment_position_index(session[:game].moves,
                                                                      start_search_from_move_idx,
                                                                      learning_side)

    if new_critical_position_index
      session[:current_move_index] = new_critical_position_index
      build_critical_moment_response(learning_side, "Jumped to next critical moment for #{learning_side}.")
    else
      build_critical_moment_response(learning_side,
                                     "No further critical moments found for #{learning_side} from this point.")
    end
  end

  def build_critical_moment_response(_learning_side, message)
    last_move = get_last_move_info(session[:game], session[:current_move_index])
    json_response({
                    fen: current_board_fen,
                    move_index: session[:current_move_index],
                    total_positions: session[:game].positions.size,
                    last_move: last_move,
                    message: message
                  })
  end

  # API endpoint to go to the start of the game
  post '/game/go_to_start' do
    return json_response({ error: 'No game loaded.' }, 404) unless game_loaded?

    session[:current_move_index] = 0
    last_move = get_last_move_info(session[:game], session[:current_move_index]) # Will be nil
    json_response({
                    fen: current_board_fen,
                    move_index: session[:current_move_index],
                    total_positions: session[:game].positions.size,
                    last_move: last_move,
                    message: 'Went to start of the game.'
                  })
  end

  # API endpoint to go to the end of the game
  post '/game/go_to_end' do
    return json_response({ error: 'No game loaded.' }, 404) unless game_loaded?

    session[:current_move_index] = session[:game].positions.size - 1
    last_move = get_last_move_info(session[:game], session[:current_move_index])
    json_response({
                    fen: current_board_fen,
                    move_index: session[:current_move_index],
                    total_positions: session[:game].positions.size,
                    last_move: last_move,
                    message: 'Went to end of the game.'
                  })
  end

  # API endpoint to set the game to a specific move index
  post '/game/set_move_index' do
    return json_response({ error: 'No game loaded.' }, 404) unless game_loaded?

    begin
      params = JSON.parse(request.body.read)
      target_move_index = params['move_index']
    rescue JSON::ParserError
      return json_response({ error: 'Invalid JSON in request body' }, 400)
    end

    unless target_move_index.is_a?(Integer) && target_move_index >= 0 &&
           target_move_index < session[:game].positions.size
      return json_response({ error: "Invalid move_index: #{target_move_index}" }, 400)
    end

    session[:current_move_index] = target_move_index
    last_move = get_last_move_info(session[:game], session[:current_move_index])
    # Include player names as other navigation endpoints do
    white_player = session[:game].tags['White'] || 'Unknown White'
    black_player = session[:game].tags['Black'] || 'Unknown Black'

    json_response({
                    fen: current_board_fen,
                    move_index: session[:current_move_index],
                    total_positions: session[:game].positions.size,
                    last_move: last_move,
                    white_player: white_player,
                    black_player: black_player,
                    message: "Game set to move index #{target_move_index}."
                  })
  end

  # API to assess if a user's move is a good alternative to the correct one
  # Returns continuation line if the move is good
  post '/game/validate_critical_move' do
    return json_response({ error: 'No game loaded.' }, 404) unless game_loaded?

    params = parse_json_body
    return params if params.is_a?(Hash) && params[:error]

    fen = params['fen']
    user_move_uci = params['user_move_uci']
    good_move_uci = params['good_move_uci']

    unless fen && user_move_uci && good_move_uci
      return json_response({ error: 'Missing fen, user_move_uci, or good_move_uci' }, 400)
    end

    validate_and_get_continuation(fen, user_move_uci, good_move_uci)
  end

  def validate_and_get_continuation(fen, user_move_uci, good_move_uci)
    analyzer = Analyzer.new
    begin
      is_good_enough = analyzer.good_enough_move?(fen, user_move_uci, good_move_uci)
      response = { good_enough: is_good_enough }

      if is_good_enough
        variation_sans = calculate_continuation_line(fen, user_move_uci, analyzer)
        response[:variation_sans] = variation_sans if variation_sans
      end

      json_response(response)
    rescue Analyzer::EngineError => e
      json_response({ error: "Analysis engine error: #{e.message}" }, 500)
    ensure
      analyzer.close
    end
  end

  def calculate_continuation_line(fen, user_move_uci, analyzer)
    require_relative 'lib/uci_to_san_converter'
    require_relative 'lib/move_translator'
    uci_converter = UciToSanConverter.new
    user_move_san = uci_converter.convert(fen, user_move_uci)

    translator = MoveTranslator.new
    translator.load_game_from_fen(fen)
    translator.translate_move(user_move_san)
    fen_after_user_move = translator.board_as_fen

    continuation_analysis = analyzer.evaluate_best_move(fen_after_user_move)
    return nil unless continuation_analysis && continuation_analysis[:variation]

    full_variation = [user_move_uci, continuation_analysis[:move]] + continuation_analysis[:variation]
    require_relative 'lib/game_editor'
    game_editor = GameEditor.new
    variation_sequence = game_editor.build_variation_sequence(fen, full_variation, 8)
    variation_sequence.map(&:notation)
  end

  # API endpoint to add a variation to the current move in the loaded game
  post '/game/add_variation' do
    return json_response({ error: 'No game loaded.' }, 404) unless game_loaded?

    params = parse_json_body
    return params if params.is_a?(Hash) && params[:error]

    move_index = params['move_index']
    variation_sans = params['variation_sans']
    user_move_san = params['user_move_san']

    unless move_index && variation_sans && user_move_san
      return json_response({ error: 'Missing move_index, variation_sans, or user_move_san' }, 400)
    end

    add_variation_to_move(move_index, variation_sans)
  end

  def add_variation_to_move(move_index, variation_sans)
    validation_error = validate_move_index(move_index)
    return validation_error if validation_error

    move = session[:game].moves[move_index]
    variation_sequence = build_and_annotate_variation(move_index, variation_sans)
    attach_variation_to_move(move, variation_sequence)
  rescue StandardError => e
    puts "ERROR: Failed to add variation: #{e.message}"
    puts e.backtrace.join("\n")
    json_response({ error: "Failed to add variation: #{e.message}" }, 500)
  end

  def validate_move_index(move_index)
    return nil if move_index.is_a?(Integer) && move_index >= 0 && move_index < session[:game].moves.size

    json_response({ error: "Invalid move_index: #{move_index}" }, 400)
  end

  def build_and_annotate_variation(move_index, variation_sans)
    fen_before = session[:game].positions[move_index].to_fen.to_s
    variation_sequence = build_variation_sequence(fen_before, variation_sans)
    variation_sequence[0].comment = 'Alternative line found during review' if variation_sequence.any?
    variation_sequence
  end

  def attach_variation_to_move(move, variation_sequence)
    move.variations ||= []
    move.variations << variation_sequence
    json_response({
                    success: true,
                    message: 'Variation added successfully',
                    variation_count: move.variations.size
                  })
  end

  def build_variation_sequence(fen_before, variation_sans)
    variation_sequence = []
    current_fen = fen_before

    variation_sans.each do |san_move|
      variation_sequence << PGN::MoveText.new(san_move)
      require_relative 'lib/move_translator'
      translator = MoveTranslator.new
      translator.load_game_from_fen(current_fen)
      translator.translate_move(san_move)
      current_fen = translator.board_as_fen
    rescue StandardError => e
      puts "Warning: Failed to process variation move #{san_move}: #{e.message}"
      break
    end

    variation_sequence
  end

  # API endpoint to save the current game back to its PGN file
  post '/game/save' do
    return json_response({ error: 'No game loaded.' }, 404) unless game_loaded?
    return json_response({ error: 'No PGN file path stored.' }, 404) unless session[:pgn_file_path]

    begin
      require_relative 'lib/pgn_writer'
      require_relative 'lib/game_editor'

      # Before saving, unshift annotations back to their original positions
      # (add_blunder_annotations places $201 on move i-1, which is correct for PGN)
      game_editor = GameEditor.new
      game_editor.unshift_critical_annotations(session[:game])

      # Serialize the game to PGN
      writer = PGNWriter.new
      annotated_pgn = writer.write(session[:game])

      # Write to file
      File.write(session[:pgn_file_path], annotated_pgn)

      # Re-shift annotations for in-memory use (for consistency with loaded games)
      game_editor.shift_critical_annotations(session[:game])

      json_response({
                      success: true,
                      message: 'Game saved successfully',
                      file_path: session[:pgn_file_path]
                    })
    rescue StandardError => e
      puts "ERROR: Failed to save game: #{e.message}"
      puts e.backtrace.join("\n")
      json_response({ error: "Failed to save game: #{e.message}" }, 500)
    end
  end

  # API endpoint to upload a PGN file
  post '/api/upload_pgn' do
    # Check if PGN_DIR is configured
    pgn_dir = ENV.fetch('PGN_DIR', nil)
    if pgn_dir.nil? || pgn_dir.empty? || !Dir.exist?(pgn_dir)
      return json_response({ error: 'PGN_DIR not configured or directory does not exist' }, 500)
    end

    # Check if file was uploaded
    unless params[:file] && params[:file][:tempfile]
      return json_response({ error: 'No file uploaded. Please provide a file parameter.' }, 400)
    end

    tempfile = params[:file][:tempfile]
    original_filename = params[:file][:filename]

    # Validate file extension
    unless original_filename.end_with?('.pgn')
      return json_response({ error: 'Invalid file type. Only .pgn files are allowed.' }, 400)
    end

    # Read and validate PGN content
    begin
      pgn_content = tempfile.read
      tempfile.rewind

      # Validate it's parseable PGN
      pgn_content = ensure_pgn_has_result_termination(pgn_content)
      games = PGN.parse(pgn_content.dup)
      return json_response({ error: 'No valid games found in PGN file' }, 400) if games.empty?

      # Return info about the uploaded file
      json_response({
                      filename: original_filename,
                      game_count: games.size,
                      size: pgn_content.bytesize,
                      message: 'PGN file validated successfully. Use /api/analyze_and_save to process and save it.'
                    })
    rescue StandardError => e
      json_response({ error: "Invalid PGN file: #{e.message}" }, 400)
    end
  end

  # API endpoint to analyze a PGN and save it to PGN_DIR
  post '/api/analyze_and_save' do
    require_relative 'lib/pgn_writer'

    pgn_dir = ENV.fetch('PGN_DIR', nil)
    if pgn_dir.nil? || pgn_dir.empty? || !Dir.exist?(pgn_dir)
      return json_response({ error: 'PGN_DIR not configured or directory does not exist' }, 500)
    end

    pgn_data = extract_pgn_from_request
    return pgn_data if pgn_data.is_a?(String) # Error response (JSON string)
    return pgn_data if pgn_data.is_a?(Hash) && pgn_data[:error]

    analyze_and_save_pgn(pgn_data[:content], pgn_data[:filename], pgn_dir)
  end

  def extract_pgn_from_request
    if file_uploaded?
      extract_from_file_upload
    elsif json_request?
      extract_from_json_body
    else
      json_response({ error: 'Invalid request. Provide either file upload or JSON with pgn_content.' }, 400)
    end
  end

  def file_uploaded?
    params[:file] && params[:file][:tempfile]
  end

  def json_request?
    request.content_type&.include?('application/json')
  end

  def extract_from_file_upload
    tempfile = params[:file][:tempfile]
    original_filename = params[:file][:filename]
    pgn_content = tempfile.read
    validate_and_return_pgn_data(pgn_content, original_filename)
  end

  def extract_from_json_body
    body_params = JSON.parse(request.body.read)
    pgn_content = body_params['pgn_content']
    original_filename = body_params['filename'] || 'uploaded_game.pgn'
    validate_and_return_pgn_data(pgn_content, original_filename)
  rescue JSON::ParserError
    json_response({ error: 'Invalid JSON in request body' }, 400)
  end

  def validate_and_return_pgn_data(pgn_content, original_filename)
    return json_response({ error: 'No PGN content provided' }, 400) unless pgn_content && !pgn_content.empty?

    { content: pgn_content, filename: original_filename }
  end

  def analyze_and_save_pgn(pgn_content, original_filename, pgn_dir)
    pgn_content = ensure_pgn_has_result_termination(pgn_content)
    games = PGN.parse(pgn_content.dup)
    return json_response({ error: 'No valid games found in PGN' }, 400) if games.empty?

    game = games.first
    annotated_pgn = annotate_game_with_blunders(game)
    output_path = save_annotated_pgn(annotated_pgn, original_filename, pgn_dir)
    return output_path if output_path.is_a?(Hash) && output_path[:error]

    scan_pgn_directory
    file_id = generate_stable_file_id(output_path)

    json_response({
                    success: true,
                    filename: File.basename(output_path),
                    path: output_path,
                    file_id: file_id,
                    game_count: 1,
                    message: 'Game annotated and saved successfully'
                  })
  rescue StandardError => e
    puts "ERROR: Failed to analyze and save PGN: #{e.message}"
    puts e.backtrace.join("\n")
    json_response({ error: "Failed to process PGN: #{e.message}" }, 500)
  end

  def annotate_game_with_blunders(game)
    game_editor = GameEditor.new
    game_editor.add_blunder_annotations(game)
    require_relative 'lib/pgn_writer'
    writer = PGNWriter.new
    writer.write(game)
  end

  def save_annotated_pgn(annotated_pgn, original_filename, pgn_dir)
    safe_filename = sanitize_filename(original_filename)
    unique_filename = generate_unique_filename(safe_filename)
    output_path = File.join(pgn_dir, unique_filename)

    return json_response({ error: 'Invalid file path' }, 400) unless within_pgn_dir?(output_path)

    File.write(output_path, annotated_pgn)
    output_path
  end
  # --- End Routes ---
end
