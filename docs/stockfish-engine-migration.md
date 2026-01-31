# Stockfish Engine Migration

## Overview

This application now uses an internal `StockfishEngine` class instead of the `stockfish` gem for communicating with the Stockfish chess engine. This change provides better compatibility with Stockfish 17+ and eliminates frozen string literal issues.

## What Changed

### Added Files

- **lib/stockfish_engine.rb** - New internal UCI engine implementation
  - Lightweight wrapper around Stockfish binary
  - Direct UCI protocol communication via `Open3.popen3`
  - Supports all features needed by the application

- **test/stockfish_engine_test.rb** - Comprehensive tests for the new engine class

### Modified Files

- **Gemfile** - Removed `stockfish` gem dependency
- **lib/analyzer.rb** - Updated to use `StockfishEngine` instead of `Stockfish::Engine`
- **test/analyzer_test.rb** - Updated test mocks to use `StockfishEngine`
- **CLAUDE.md** - Updated documentation to reflect the changes
- **scripts/fix_stockfish_warning.rb** - Marked as deprecated

## Benefits

1. **Better Stockfish 17+ Compatibility** - Direct UCI communication works reliably with modern Stockfish versions
2. **No Gem Patches Required** - No need to run fix scripts after gem updates
3. **Simpler Dependencies** - One less gem to manage
4. **Full Control** - We can customize the UCI communication as needed
5. **Better Error Handling** - More granular control over timeouts and error conditions

## Implementation Details

### UCI Protocol

The `StockfishEngine` class implements the UCI (Universal Chess Interface) protocol:

- Spawns Stockfish process using `Open3.popen3`
- Initializes UCI mode with `uci` command
- Configures engine options with `setoption` commands
- Sets positions with `position fen` commands
- Analyzes with `go depth` or `go nodes` commands
- Reads output until `bestmove` is received

### API Compatibility

The new `StockfishEngine` class provides the same interface as the old `Stockfish::Engine`:

```ruby
# Initialize engine
engine = StockfishEngine.new('stockfish')

# Execute UCI commands
engine.execute('setoption name Hash value 128')

# Set MultiPV
engine.multipv(3)

# Analyze position
result = engine.analyze(fen, depth: 14)

# Close engine
engine.close
```

### Error Handling

- `StockfishEngine::EngineError` - General engine errors (e.g., binary not found)
- `StockfishEngine::CommunicationError` - Communication failures with the engine

### Timeout Handling

- Read operations use `IO.select` with 30-second timeout
- Prevents hanging if engine stops responding
- Graceful cleanup on errors

## Testing

All existing tests continue to pass:

```bash
bundle exec rake test
# 187 runs, 447 assertions, 0 failures, 0 errors, 0 skips
```

New tests verify:
- Engine initialization and startup
- UCI command execution
- Position analysis
- MultiPV support
- Error handling
- Resource cleanup

## Migration Notes

No code changes are required in application code. The `Analyzer` class continues to work exactly as before, but now uses the internal `StockfishEngine` instead of the gem.

The only user-visible change is that you no longer need to:
1. Run `scripts/fix_stockfish_warning.rb` after installing gems
2. Worry about Stockfish gem compatibility with newer Stockfish versions
