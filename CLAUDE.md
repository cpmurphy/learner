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
# Run a single test file
bundle exec ruby -Ilib:test test/game_editor_test.rb

# Run the server (requires PGN_DIR environment variable)
PGN_DIR=./test/data bundle exec puma config.ru

# Lint code
# IMPORTANT: do not consider a task done if rubocop still triggers warnings
bundle exec rubocop
```

### JavaScript Frontend

```bash
# Copy third-party assets (cm-chessboard, chess.js) after npm install
npm run copy-all
```

### Public-site hardening

The app can run publicly (see README "Running It Publicly"):
- **Owner-only library:** `LearnerApp::OWNER_ROUTES` (`/api/pgn_files`, `/api/load_game`, `/game/save`, `/api/upload_pgn`, `/api/analyze_and_save`) return 403 unless `owner?`; anonymous visitors never see library games. With `OWNER_PASSWORD_HASH` set, the owner logs in at `/login` (scrypt via `lib/owner_password.rb`, hashes made by `bin/owner-password`). Without it, development and test treat everyone as the owner and production allows no writes. The frontend asks `GET /api/session` which controls to show (`public/scripts/session_info.js`).
- **Anonymous analysis:** `POST /api/analyze` (anyone) analyzes a pasted game and keeps it only in the session (`session[:analysis]`, `pgn_file_path` nil); `GET /api/analysis` loads it for `/game?id=analysis`. It is never written to `PGN_DIR`, put in the annotation cache, or logged (errors log the class only). Input is bounded (`MAX_ANALYSIS_PGN_BYTES`, `MAX_ANALYSIS_PLIES`), must pass `lib/game_legality.rb` (legal moves from the standard start, so the engine never sees impossible positions), and runs in `ANALYSIS_SLOTS` (`lib/analysis_slots.rb`, `MAX_CONCURRENT_ANALYSES`).
- **Rate limits:** `lib/rate_limits.rb` (Rack::Attack with the in-memory `lib/memory_rate_store.rb`), keyed by `ClientNetwork.key` (IPv6 by /64). `test/test_helper.rb` sets `RATE_LIMITS=off`; tests that exercise limits set `Rack::Attack.enabled = true` and reset it.
- **Client address:** `lib/client_network.rb` makes `request.ip` believe `X-Forwarded-For` only from `TRUSTED_PROXIES` (default loopback), instead of Rack's default of every private address.
- **Sessions:** `lib/bounded_session_pool.rb` replaces `Rack::Session::Pool`, which stores an entry for every unknown cookie and never expires any.
- **Analysis cache:** `lib/annotation_cache.rb` keeps whole-game analysis per library file (keyed by path, size and mtime) and hands each session a `Marshal` copy.
- Rack::Protection (including `HttpOrigin`, the CSRF defence for owner routes) is on only in production, as before; `test/app_owner_test.rb` enables it to test cross-site requests behind proxy headers.

### Deployment and the engine service

`deploy/CLAUDE.md` holds deployment guidance. The engine service lives in the
separate [stockfish-pool](https://github.com/cpmurphy/stockfish-pool) repo.
- **racc:** `pgn2` needs `racc`, which must stay in the Gemfile; production bundles without development gems otherwise fail to boot.
- **stockfish-pool:** Client gem is pinned by git tag in the Gemfile; keep that tag equal to `POOL_REF` (`bin/check-pool-ref` enforces it in CI, deploy, image builds and the local pre-commit hook). `bin/deploy.sh` / `deploy/build-images.sh` build the pool image from that ref via `bin/pool-checkout`. For local client edits: `bundle config local.stockfish_pool_client /path/to/stockfish-pool/client`.
- **Chess rules:** stockfish-pool owns `StockfishPool::Rules`. Refresh `lib/chess_rules/` with `bin/sync-chess-rules` (CI runs `--check`). `san.rb` is app-only.

### Stockfish Engine

The Stockfish directory contains a git submodule for the Stockfish chess engine. This is built separately and not modified as part of this project. The application uses an internal `StockfishEngine` class (lib/stockfish_engine.rb) to communicate with the Stockfish binary via UCI protocol, rather than using the `stockfish` gem. This approach provides better compatibility with Stockfish 17+ and avoids frozen string literal issues.

## Key Concepts

**Position Index vs Move Index:**
- The `session[:current_move_index]` represents the position index (0 = starting position)
- Position N corresponds to the board state after move N-1 in the moves array
- Position 0 has no preceding move
- `game.moves[0]` is the first move, leading to `game.positions[1]`

**Critical Moments ($201 annotation):**
- Critical moments are blunders or important positions marked with the $201 NAG (Numeric Annotation Glyph)
- These are either annotated manually in SCID or automatically detected by the `GameEditor`
- When a critical moment is found, variations in the PGN provide the suggested better move
- The PGN parser may attach $201 to the previous move; `shift_critical_annotations` moves it to the correct one

## Important Notes

- Sessions store the entire parsed game object, so they can be large
- When writing tests for move translation, ensure board state is properly maintained across multiple moves
