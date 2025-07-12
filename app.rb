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
  end
  # --- End Helpers ---

  def initialize
    super
    @available_pgns = [] # Holds {id: string, name: string, path: string} for discovered PGN files
    pgn_dir_path = ENV.fetch('PGN_DIR', nil)

    if pgn_dir_path.nil? || pgn_dir_path.empty?
      puts '---------------------------------------------------------------------------------------'
      puts 'ERROR: PGN_DIR environment variable not set.'
      puts 'Please provide the path to a directory containing PGN files.'
      puts 'Example: PGN_DIR=./test/data bundle exec puma config.ru'
      puts 'The application will start, but game functionality will be disabled until a PGN is loaded via API.'
      puts '---------------------------------------------------------------------------------------'
    elsif !Dir.exist?(pgn_dir_path)
      puts '---------------------------------------------------------------------------------------'
      puts "ERROR: PGN directory not found at path: #{pgn_dir_path}"
      puts 'Please ensure the PGN_DIR environment variable points to an existing directory.'
      puts 'The application will start, but game functionality will be disabled.'
      puts '---------------------------------------------------------------------------------------'
    else
      puts "Scanning PGN directory: #{pgn_dir_path}"
      pgn_files = Dir.glob(File.join(pgn_dir_path, '*.pgn'))
      if pgn_files.empty?
        puts "No PGN files found in #{pgn_dir_path}."
      else
        pgn_files.each_with_index do |file_path, index|
          filename = File.basename(file_path)
          # Ensure path is absolute and normalized for security/consistency
          abs_path = File.expand_path(file_path)
          # Basic check to ensure the file is within the intended PGN_DIR
          # This is a simple check; more robust sandboxing might be needed for untrusted PGN_DIR values
          if abs_path.start_with?(File.expand_path(pgn_dir_path))
            game_count = 0
            begin
              pgn_content_for_count = File.read(abs_path)
              games_in_file = PGN.parse(pgn_content_for_count)
              game_count = games_in_file.size
            rescue StandardError => e
              puts "WARNING: Could not parse PGN file #{filename} to count games. Error: #{e.message}. Assuming 0 games."
              game_count = 0 # Or handle as an error indicator if preferred
            end
            @available_pgns << {
              id: index.to_s, # Use index as a simple, safe ID
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
  end

  # --- Routes ---

  # Serve index.html for the root path
  get '/' do
    send_file File.join(settings.public_folder, 'index.html')
  end

  # API endpoint to list available PGN files
  get '/api/pgn_files' do
    # Return id, name, and game_count
    files_for_client = @available_pgns.map do |pgn_meta|
      { id: pgn_meta[:id], name: pgn_meta[:name], game_count: pgn_meta[:game_count] }
    end
    json_response(files_for_client)
  end

  # API endpoint to load the first game from a selected PGN file
  post '/api/load_game' do
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
      games_in_file = PGN.parse(pgn_content)

      if games_in_file.empty?
        session[:game] = nil # Unload any previously loaded game
        session[:current_move_index] = 0
        return json_response({ error: "No games found in PGN file: #{pgn_meta[:name]}" }, 400)
      end

      session[:game] = games_in_file.first # Load the first game
      GameEditor.shift_critical_annotations(session[:game])
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
      json_response({ good_enough: is_good_enough })
    rescue Analyzer::EngineError => e
      json_response({ error: "Analysis engine error: #{e.message}" }, 500)
    ensure
      analyzer.close
    end
  end
  # --- End Routes ---
end
