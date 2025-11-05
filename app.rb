# frozen_string_literal: true

require 'sinatra'
require 'pgn'
require 'json'
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
      return pgn_text unless ["1-0", "0-1", "1/2-1/2", "*"].include?(normalized_result)

      trimmed = pgn_text.rstrip
      return pgn_text if trimmed.match?(/(1-0|0-1|1\/2-1\/2|\*)\s*\z/)

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

    if pgn_dir_path.nil? || pgn_dir_path.empty?
      puts '---------------------------------------------------------------------------------------'
      puts 'ERROR: PGN_DIR environment variable not set.'
      puts 'Please provide the path to a directory containing PGN files.'
      puts 'Example: PGN_DIR=./test/data bundle exec puma config.ru'
      puts 'The application will start, but game functionality will be disabled until a PGN is loaded via API.'
      puts '---------------------------------------------------------------------------------------'
      return
    elsif !Dir.exist?(pgn_dir_path)
      puts '---------------------------------------------------------------------------------------'
      puts "ERROR: PGN directory not found at path: #{pgn_dir_path}"
      puts 'Please ensure the PGN_DIR environment variable points to an existing directory.'
      puts 'The application will start, but game functionality will be disabled.'
      puts '---------------------------------------------------------------------------------------'
      return
    end

    puts "Scanning PGN directory: #{pgn_dir_path}"
    pgn_files = Dir.glob(File.join(pgn_dir_path, '*.pgn'))
    # Sort files by last modified time descending (newest first)
    begin
      pgn_files.sort_by! { |file_path| File.mtime(file_path) }
      pgn_files.reverse!
    rescue StandardError => e
      puts "WARNING: Failed to sort PGN files by modified time: #{e.message}. Falling back to default order."
    end
    if pgn_files.empty?
      puts "No PGN files found in #{pgn_dir_path}."
    else
      pgn_files.each_with_index do |file_path, index|
        filename = File.basename(file_path)
        # Ensure path is absolute and normalized for security/consistency
        abs_path = File.expand_path(file_path)
        # Basic check to ensure the file is within the intended PGN_DIR
        if abs_path.start_with?(File.expand_path(pgn_dir_path))
          game_count = 0
          begin
            pgn_content_for_count = File.read(abs_path)
            pgn_content_for_count = ensure_pgn_has_result_termination(pgn_content_for_count)
            games_in_file = PGN.parse(pgn_content_for_count)
            game_count = games_in_file.size
          rescue StandardError => e
            puts "WARNING: Could not parse PGN file #{filename} to count games. Error: #{e.message}. Assuming 0 games."
            game_count = 0
          end
          @available_pgns << {
            id: index.to_s,
            name: filename,
            path: abs_path,
            game_count: game_count
          }
        else
          puts "WARNING: File #{file_path} is outside the PGN_DIR and will be ignored."
        end
      end
      puts "Found #{@available_pgns.size} PGN files. Ready for selection via API."
    end
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

    # Return id, name, and game_count
    files_for_client = @available_pgns.map do |pgn_meta|
      { id: pgn_meta[:id], name: pgn_meta[:name], game_count: pgn_meta[:game_count] }
    end
    json_response(files_for_client)
  end

  # API endpoint to load the first game from a selected PGN file
  post '/api/load_game' do
    # Ensure the PGN list (and IDs) reflect the latest directory state and sort order
    scan_pgn_directory

    begin
      params = JSON.parse(request.body.read)
    rescue JSON::ParserError
      return json_response({ error: 'Invalid JSON in request body' }, 400)
    end

    pgn_file_id = params['pgn_file_id']

    return json_response({ error: 'Missing pgn_file_id parameter' }, 400) unless pgn_file_id

    pgn_meta = @available_pgns.find { |p| p[:id] == pgn_file_id }

    return json_response({ error: "PGN file not found for ID: #{pgn_file_id}" }, 404) unless pgn_meta

    begin
      pgn_content = File.read(pgn_meta[:path])
      pgn_content = ensure_pgn_has_result_termination(pgn_content)
      games_in_file = PGN.parse(pgn_content)

      if games_in_file.empty?
        session[:game] = nil # Unload any previously loaded game
        session[:current_move_index] = 0
        return json_response({ error: "No games found in PGN file: #{pgn_meta[:name]}" }, 400)
      end

      session[:game] = games_in_file.first # Load the first game
      session[:pgn_file_path] = pgn_meta[:path] # Store the file path for saving

      # If the PGN has no critical moment annotations, analyze it to find them.
      has_critical_moments = session[:game].moves.any? { |m| m.annotation&.include?('$201') }
      game_editor = GameEditor.new

      if has_critical_moments
        # PGN already has $201 annotations (likely from SCID or another tool).
        # These might be associated with the wrong move by the parser, so shift them.
        game_editor.shift_critical_annotations(session[:game])
      else
        # No existing annotations, so analyze and add them.
        puts 'No critical moments found in PGN, analyzing for blunders...'
        game_editor.add_blunder_annotations(session[:game])
        puts 'Blunder analysis complete.'
        # Note: We do NOT call shift_critical_annotations here because annotations
        # added by add_blunder_annotations are already on the correct move.
      end

      session[:current_move_index] = 0

      puts "Loaded game from PGN: #{pgn_meta[:name]}. Board positions: #{session[:game].positions.size}"
      last_move = get_last_move_info(session[:game], session[:current_move_index]) # Will be nil for index 0

      # Check for initial critical moment for White (default learning side on frontend)
      # Search from the very first move (index 0 of session[:game].moves)
      has_initial_critical_for_white = !find_critical_moment_position_index(session[:game].moves, 0, 'white').nil?

      white_player = session[:game].tags['White'] || 'Unknown White'
      black_player = session[:game].tags['Black'] || 'Unknown Black'

      json_response({
                      fen: current_board_fen,
                      move_index: session[:current_move_index],
                      total_positions: session[:game].positions.size,
                      last_move: last_move,
                      message: "Successfully loaded game from #{pgn_meta[:name]}",
                      has_initial_critical_moment_for_white: has_initial_critical_for_white,
                      white_player: white_player,
                      black_player: black_player
                    })
    rescue StandardError => e
      session[:game] = nil # Ensure game is not partially loaded
      session[:current_move_index] = 0
      puts "ERROR: Could not parse PGN file: #{pgn_meta[:path]}."
      puts "Details: #{e.message}"
      json_response({ error: "Could not parse PGN file: #{pgn_meta[:name]}. Details: #{e.message}" }, 500)
    end
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
      json_response({ fen: current_board_fen, move_index: session[:current_move_index], message: 'Already at the last move.',
                      last_move: last_move })
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
      json_response({ fen: current_board_fen, move_index: session[:current_move_index], message: 'Already at the first move.',
                      last_move: last_move })
    end
  end

  # API endpoint to go to the next critical move for the learning side
  post '/game/next_critical_moment' do
    unless game_loaded?
      return json_response({ error: 'No game loaded. Please select a PGN file and load a game.' },
                           404)
    end

    begin
      params = JSON.parse(request.body.read)
      learning_side = params['learning_side'] # 'white' or 'black'
    rescue JSON::ParserError
      return json_response({ error: 'Invalid JSON in request body' }, 400)
    end

    unless %w[white black].include?(learning_side)
      return json_response({ error: "Invalid learning_side parameter. Must be 'white' or 'black'." }, 400)
    end

    # session[:current_move_index] is the current position index.
    # If current position is 0 (start), session[:game].moves[0] is the first move to check.
    # If current position is N, session[:game].moves[N] is the next move to check.
    # So, start_search_from_move_idx is session[:current_move_index].
    start_search_from_move_idx = session[:current_move_index]

    new_critical_position_index = find_critical_moment_position_index(session[:game].moves, start_search_from_move_idx,
                                                                      learning_side)

    if new_critical_position_index
      session[:current_move_index] = new_critical_position_index
      last_move = get_last_move_info(session[:game], session[:current_move_index])
      json_response({
                      fen: current_board_fen,
                      move_index: session[:current_move_index],
                      total_positions: session[:game].positions.size,
                      last_move: last_move,
                      message: "Jumped to next critical moment for #{learning_side}."
                    })
    else
      # No more critical moves found for this side from the current position
      # Return current state but with a message; session[:current_move_index] is unchanged.
      last_move = get_last_move_info(session[:game], session[:current_move_index])
      json_response({
                      fen: current_board_fen,
                      move_index: session[:current_move_index],
                      total_positions: session[:game].positions.size,
                      last_move: last_move,
                      message: "No further critical moments found for #{learning_side} from this point."
                    }, 200) # HTTP 200 OK, but with a specific message in the payload
    end
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

    unless target_move_index.is_a?(Integer) && target_move_index >= 0 && target_move_index < session[:game].positions.size
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

    begin
      params = JSON.parse(request.body.read)
      fen = params['fen']
      user_move_uci = params['user_move_uci']
      good_move_uci = params['good_move_uci']
    rescue JSON::ParserError
      return json_response({ error: 'Invalid JSON in request body' }, 400)
    end

    unless fen && user_move_uci && good_move_uci
      return json_response({ error: 'Missing fen, user_move_uci, or good_move_uci' }, 400)
    end

    analyzer = Analyzer.new
    begin
      is_good_enough = analyzer.good_enough_move?(fen, user_move_uci, good_move_uci)
      
      response = { good_enough: is_good_enough }
      
      # If the move is good enough, calculate the continuation line
      if is_good_enough
        # First convert user's UCI move to SAN so we can apply it
        require_relative 'lib/uci_to_san_converter'
        require_relative 'lib/move_translator'
        uci_converter = UciToSanConverter.new
        user_move_san = uci_converter.convert(fen, user_move_uci)
        
        # Apply the user's move to get the position after their move
        translator = MoveTranslator.new
        translator.load_game_from_fen(fen)
        translator.translate_move(user_move_san)
        fen_after_user_move = translator.board_as_fen
        
        # Get the best continuation from the position after the user's move
        # This will return moves starting with the opponent's response
        continuation_analysis = analyzer.evaluate_best_move(fen_after_user_move)
        
        if continuation_analysis && continuation_analysis[:variation]
          # continuation_analysis[:move] is the opponent's best response (in UCI)
          # continuation_analysis[:variation] is the continuation after that (also UCI)
          # We prepend the user's move to get the full line
          full_variation = [user_move_uci, continuation_analysis[:move]] + continuation_analysis[:variation]
          
          puts "DEBUG: Full variation UCI: #{full_variation.inspect}"
          
          # Convert UCI moves to SAN
          require_relative 'lib/game_editor'
          game_editor = GameEditor.new
          variation_sequence = game_editor.build_variation_sequence(fen, full_variation, 8)
          variation_sans = variation_sequence.map(&:notation)
          
          puts "DEBUG: Variation SAN after conversion: #{variation_sans.inspect}"
          
          response[:variation_sans] = variation_sans
        end
      end
      
      json_response(response)
    rescue Analyzer::EngineError => e
      json_response({ error: "Analysis engine error: #{e.message}" }, 500)
    ensure
      analyzer.close
    end
  end

  # API endpoint to add a variation to the current move in the loaded game
  post '/game/add_variation' do
    return json_response({ error: 'No game loaded.' }, 404) unless game_loaded?

    begin
      params = JSON.parse(request.body.read)
      move_index = params['move_index'] # The move index before the variation starts
      variation_sans = params['variation_sans'] # Array of SAN moves for the variation
      user_move_san = params['user_move_san'] # The user's move in SAN
    rescue JSON::ParserError
      return json_response({ error: 'Invalid JSON in request body' }, 400)
    end

    unless move_index && variation_sans && user_move_san
      return json_response({ error: 'Missing move_index, variation_sans, or user_move_san' }, 400)
    end

    begin
      # Ensure move_index is valid
      unless move_index.is_a?(Integer) && move_index >= 0 && move_index < session[:game].moves.size
        return json_response({ error: "Invalid move_index: #{move_index}" }, 400)
      end

      move = session[:game].moves[move_index]
      
      # Build variation sequence from SAN moves
      require_relative 'lib/game_editor'
      game_editor = GameEditor.new
      
      # Get FEN before the move where variation starts
      fen_before = session[:game].positions[move_index].to_fen.to_s
      
      # Build variation sequence from SAN moves
      variation_sequence = []
      current_fen = fen_before
      
      variation_sans.each do |san_move|
        begin
          variation_sequence << PGN::MoveText.new(san_move)
          
          # Update FEN by applying the move
          require_relative 'lib/move_translator'
          translator = MoveTranslator.new
          translator.load_game_from_fen(current_fen)
          translator.translate_move(san_move)
          current_fen = translator.board_as_fen
        rescue StandardError => e
          puts "Warning: Failed to process variation move #{san_move}: #{e.message}"
          break
        end
      end

      # Add comment to first move
      if variation_sequence.any?
        variation_sequence[0].comment = "Alternative line found during review"
      end

      # Add variation to the move
      move.variations ||= []
      move.variations << variation_sequence

      json_response({
        success: true,
        message: 'Variation added successfully',
        variation_count: move.variations.size
      })
    rescue StandardError => e
      puts "ERROR: Failed to add variation: #{e.message}"
      puts e.backtrace.join("\n")
      json_response({ error: "Failed to add variation: #{e.message}" }, 500)
    end
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
      puts "Saved game to #{session[:pgn_file_path]}"
      
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
      if games.empty?
        return json_response({ error: 'No valid games found in PGN file' }, 400)
      end

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

    # Check if PGN_DIR is configured
    pgn_dir = ENV.fetch('PGN_DIR', nil)
    if pgn_dir.nil? || pgn_dir.empty? || !Dir.exist?(pgn_dir)
      return json_response({ error: 'PGN_DIR not configured or directory does not exist' }, 500)
    end

    begin
      # Parse request body
      if params[:file] && params[:file][:tempfile]
        # File upload
        tempfile = params[:file][:tempfile]
        original_filename = params[:file][:filename]
        pgn_content = tempfile.read
      elsif request.content_type&.include?('application/json')
        # JSON body with PGN content
        body_params = JSON.parse(request.body.read)
        pgn_content = body_params['pgn_content']
        original_filename = body_params['filename'] || 'uploaded_game.pgn'
      else
        return json_response({ error: 'Invalid request. Provide either file upload or JSON with pgn_content.' }, 400)
      end

      unless pgn_content && !pgn_content.empty?
        return json_response({ error: 'No PGN content provided' }, 400)
      end

      # Parse PGN
      pgn_content = ensure_pgn_has_result_termination(pgn_content)
      games = PGN.parse(pgn_content.dup)
      if games.empty?
        return json_response({ error: 'No valid games found in PGN' }, 400)
      end

      # Analyze the first game with Stockfish
      game = games.first
      game_editor = GameEditor.new

      puts "Annotating game with Stockfish..."
      game_editor.add_blunder_annotations(game)
      # Note: shift_critical_annotations is NOT called because annotations
      # added by add_blunder_annotations are already on the correct move.
      puts "Annotation complete."

      # Serialize to PGN
      writer = PGNWriter.new
      annotated_pgn = writer.write(game)

      # Generate safe filename
      safe_filename = sanitize_filename(original_filename)
      unique_filename = generate_unique_filename(safe_filename)
      output_path = File.join(pgn_dir, unique_filename)

      # Security check: ensure output path is within PGN_DIR
      unless within_pgn_dir?(output_path)
        return json_response({ error: 'Invalid file path' }, 400)
      end

      # Write to file
      File.write(output_path, annotated_pgn)
      puts "Saved annotated PGN to #{output_path}"

      # Refresh the PGN file list
      scan_pgn_directory

      json_response({
        success: true,
        filename: unique_filename,
        path: output_path,
        game_count: 1,
        message: 'Game annotated and saved successfully'
      })
    rescue JSON::ParserError
      json_response({ error: 'Invalid JSON in request body' }, 400)
    rescue StandardError => e
      puts "ERROR: Failed to analyze and save PGN: #{e.message}"
      puts e.backtrace.join("\n")
      json_response({ error: "Failed to process PGN: #{e.message}" }, 500)
    end
  end
  # --- End Routes ---
end
