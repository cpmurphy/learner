# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a chess learning tool that helps users learn from their mistakes by playing through annotated games. Users can:
- Load PGN (Portable Game Notation) files with annotations
- Navigate through games move by move
- Jump to "critical moments" (mistakes/blunders marked with $201 annotation)
- Practice finding better moves at critical positions
- Have their alternative moves evaluated by Stockfish

The application consists of a Ruby/Sinatra backend serving a REST API and a vanilla JavaScript frontend.

## Development Commands

### Ruby Backend

```bash
# Install dependencies
bundle install

# Run tests
bundle exec rake test

# Run a single test file
bundle exec ruby -Ilib:test test/game_editor_test.rb

# Run the server (requires PGN_DIR environment variable)
PGN_DIR=./test/data bundle exec puma config.ru

# Lint code
bundle exec rubocop
```

### JavaScript Frontend

```bash
# Install dependencies
npm install

# Copy third-party assets (cm-chessboard, chess.js)
npm run copy-all

# Run JavaScript tests
npm test

# Run tests once (non-watch mode)
npm run test_once

# Run tests with coverage
npm run coverage
```

### Stockfish Engine

The Stockfish directory contains a git submodule for the Stockfish chess engine. This is built separately and not modified as part of this project. The engine binary is referenced by the `stockfish` gem, which uses the system `stockfish` command by default.

## Architecture

### Backend Structure (Ruby/Sinatra)

**app.rb** - Main Sinatra application
- Manages PGN file discovery from `PGN_DIR` environment variable
- Provides REST API endpoints for game navigation
- Stores game state in session (current game, move index)
- Automatically analyzes games without $201 annotations using Stockfish

**lib/game_editor.rb** - Game annotation and modification
- `add_blunder_annotations(game)` - Analyzes a game with Stockfish to find blunders (moves losing >1.4 pawns), adds $201 annotations, and adds variations showing the best move
- `shift_critical_annotations(game)` - Moves $201 annotations to the correct move (the PGN parser may associate them with the previous move)
- When a blunder is detected, creates a variation with the best move in SAN format and adds a comment explaining the advantage

**lib/analyzer.rb** - Stockfish engine wrapper
- `best_moves(fen, multipv)` - Returns the top N moves for a position
- `evaluate_move(fen, move)` - Evaluates a specific move from a position
- `good_enough_move?(fen, user_move_uci, good_move_uci)` - Determines if a user's alternative move is acceptable (>250cp advantage OR >80% as good as the suggested move)
- Contains `AnalysisParser` class that parses Stockfish UCI output

**lib/move_translator.rb** - Converts between PGN notation and UCI format
- Maintains internal board state and validates moves
- `translate_move(pgn_move)` - Converts SAN notation (e.g., "Nf3", "exd5") to UCI format (e.g., "g1f3", "e4d5")
- `board_as_fen` - Generates FEN representation of current board state
- `load_game_from_fen(fen)` - Initializes board from FEN string

**lib/translator/** - Supporting modules for move translation
- **board.rb** - Board state, piece positions, castling rights, en passant tracking
- **move_validator.rb** - Validates if a move is legal given the current board state
- **castling.rb** - Castling rights management
- **attack_detector.rb** - Check and attack detection
- **clock.rb** - Halfmove clock and fullmove number tracking

**lib/app_helpers.rb** - Helper methods for the Sinatra application
- `find_critical_moment_position_index` - Finds the next $201-annotated move for a given side
- `get_last_move_info` - Returns detailed info about the move that led to the current position

**lib/pgn_writer.rb** - PGN serialization
- `write(game)` - Serializes a PGN::Game object to PGN format string
- Handles tags, moves, annotations ($201, etc.), comments, and variations
- Wraps movetext at 80 characters per PGN standard
- Used for saving annotated games back to disk

**lib/uci_to_san_converter.rb** - UCI to SAN move conversion
- `convert(fen, uci_move)` - Converts UCI format moves (e.g., "e2e4") to SAN format (e.g., "e4")
- Handles pawn moves, piece moves, captures, castling, promotions, and disambiguation
- Used by GameEditor to convert Stockfish UCI output to PGN-compatible SAN notation for variations

### Frontend Structure (JavaScript)

The frontend is vanilla JavaScript (no framework) located in `public/`:
- **index.html** - Main HTML file
- **scripts/** - JavaScript modules
- **styles/** - CSS files
- **3rdparty-assets/** - Third-party library assets (cm-chessboard, chess.js)

The UI uses:
- `cm-chessboard` npm package for board rendering
- `chess.js` npm package for move validation on the client side

### Key Concepts

**Position Index vs Move Index:**
- The `session[:current_move_index]` represents the position index (0 = starting position)
- Position N corresponds to the board state after move N-1 in the moves array
- Position 0 has no preceding move
- `game.moves[0]` is the first move, leading to `game.positions[1]`

**Critical Moments ($201 annotation):**
- Critical moments are blunders or important positions marked with the $201 NAG (Numeric Annotation Glyph)
- These are either annotated manually in SCID or automatically detected by the `GameEditor`
- When a critical moment is found, variations in the PGN provide the suggested better move
- The shift_critical_annotations method ensures $201 is on the correct move

**Move Translation Flow:**
1. PGN moves are in Standard Algebraic Notation (SAN): "Nf3", "e4", "O-O"
2. MoveTranslator converts SAN to UCI format: "g1f3", "e2e4", "e1g1"
3. UCI format is used for Stockfish analysis
4. The translator maintains board state to disambiguate moves

**Blunder Detection:**
- A blunder is detected when the evaluation drops by more than 140 centipawns (1.4 pawns)
- For White: blunder when best_score - played_score > 140
- For Black: blunder when played_score - best_score > 140 (scores are from White's perspective)

## Testing Patterns

**Ruby Tests (Minitest):**
- Test files end with `_test.rb`
- Tests inherit from `Minitest::Test`
- Use `test/test_helper.rb` for SimpleCov setup
- Tests use Minitest's assertion methods: `assert_equal`, `assert`, `refute`, etc.

**JavaScript Tests (Vitest):**
- Vitest is configured for browser-like testing with jsdom
- Tests can be run in watch mode or once

## Important Notes

- The Stockfish directory is a git submodule and should not be modified
- The application requires the `PGN_DIR` environment variable to load games
- Sessions store the entire parsed game object, so they can be large
- The frontend expects UCI move format for communication with Stockfish
- When writing tests for move translation, ensure board state is properly maintained across multiple moves
