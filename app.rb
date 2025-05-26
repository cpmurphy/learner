require 'sinatra'
require 'pgn'
require 'json'

# --- Global State ---
# For simplicity in this skeleton, we use global variables.
# In a more complex app, consider sessions, databases, or other state management.
$game = nil
$current_move_index = 0
# --- End Global State ---

# --- Configuration ---
# This block runs once when Sinatra starts.
configure do
  # Set the directory for static files (HTML, CSS, JS)
  set :public_folder, File.join(File.dirname(__FILE__), 'public')
  # Bind to all network interfaces, useful for Docker or VMs
  set :bind, '0.0.0.0'
  # Port will be determined by the server (Puma/Rackup), typically 9292 or 4567 if specified.

  pgn_file_path = ENV['PGN_FILE']

  if pgn_file_path.nil? || pgn_file_path.empty?
    puts "---------------------------------------------------------------------------------------"
    puts "ERROR: PGN_FILE environment variable not set."
    puts "Please provide the path to a PGN file to load."
    puts "Example: PGN_FILE=test/data/threadwell-2025-05-26-01.pgn bundle exec puma config.ru"
    puts "The application will start, but game functionality will be disabled."
    puts "---------------------------------------------------------------------------------------"
    $game = nil
  elsif !File.exist?(pgn_file_path)
    puts "---------------------------------------------------------------------------------------"
    puts "ERROR: PGN file not found at path: #{pgn_file_path}"
    puts "Please ensure the PGN_FILE environment variable points to an existing file."
    puts "The application will start, but game functionality will be disabled."
    puts "---------------------------------------------------------------------------------------"
    $game = nil
  else
    puts "Loading PGN file: #{pgn_file_path}"
    begin
      pgn_content = File.read(pgn_file_path)
      games = PGN.parse(pgn_content)

      if games.empty?
        puts "ERROR: No games found in PGN file: #{pgn_file_path}"
        $game = nil
      else
        $game = games.first # We'll use the first game found in the PGN
        $current_move_index = 0 # Start at the beginning of the game
        puts "Game loaded successfully. Board positions available: #{$game.positions.size}"
      end
    rescue StandardError => e
      puts "ERROR: Could not parse PGN file: #{pgn_file_path}."
      puts "Details: #{e.message}"
      puts e.backtrace.join("\n")
      $game = nil
    end
  end
end
# --- End Configuration ---

# --- Helpers ---
helpers do
  def game_loaded?
    !$game.nil? && !$game.positions.empty?
  end

  def current_board_fen
    return nil unless game_loaded? && $game.positions[$current_move_index]
    $game.positions[$current_move_index].to_fen.to_s
  end

  def json_response(data, status_code = 200)
    content_type :json
    status status_code
    data.to_json
  end

  def get_last_move_info(move_index)
    return nil if move_index == 0 || !game_loaded?

    position = $game.positions[move_index]
    move = position.previous_move # This is a PGN::Move object

    return nil unless move # Should exist if move_index > 0 and game is loaded

    {
      number: move.number,
      turn: move.turn, # 'w' or 'b'
      san: move.notation.to_s, # Standard Algebraic Notation (e.g., "e4", "Nf3")
      comment: move.comment, # String or nil
      nags: move.nags # Array of strings (e.g., ["$1", "$201"])
    }
  end
end
# --- End Helpers ---

# --- Routes ---

# Serve index.html for the root path
get '/' do
  send_file File.join(settings.public_folder, 'index.html')
end

# API endpoint to get the current FEN
get '/game/current_fen' do
  unless game_loaded?
    return json_response({ error: "Game not loaded. Please provide a valid PGN file via PGN_FILE environment variable when starting the server." }, 404)
  end
  last_move = get_last_move_info($current_move_index)
  json_response({ fen: current_board_fen, move_index: $current_move_index, total_positions: $game.positions.size, last_move: last_move })
end

# API endpoint to go to the next move
post '/game/next_move' do
  unless game_loaded?
    return json_response({ error: "Game not loaded." }, 404)
  end

  if $current_move_index < $game.positions.size - 1
    $current_move_index += 1
    last_move = get_last_move_info($current_move_index)
    json_response({ fen: current_board_fen, move_index: $current_move_index, last_move: last_move })
  else
    # Already at the last move, return current state without error
    last_move = get_last_move_info($current_move_index)
    json_response({ fen: current_board_fen, move_index: $current_move_index, message: "Already at the last move.", last_move: last_move })
  end
end

# API endpoint to go to the previous move
post '/game/prev_move' do
  unless game_loaded?
    return json_response({ error: "Game not loaded." }, 404)
  end

  if $current_move_index > 0
    $current_move_index -= 1
    last_move = get_last_move_info($current_move_index)
    json_response({ fen: current_board_fen, move_index: $current_move_index, last_move: last_move })
  else
    # Already at the first move, return current state without error
    last_move = get_last_move_info($current_move_index) # Will be nil for index 0
    json_response({ fen: current_board_fen, move_index: $current_move_index, message: "Already at the first move.", last_move: last_move })
  end
end
# --- End Routes ---
