# Chess Learner Tool

A web-based chess learning tool that helps you learn from your games by automatically identifying critical moments (blunders and mistakes) and allowing you to practice finding better moves. This tool integrates with Stockfish to analyze your games and provides an interactive interface for studying your play.

## Quick Start

See [QUICKSTART.md](QUICKSTART.md) for the fastest way to install and run.

See [INSTALL.md](INSTALL.md) for more detailed step-by-step installation instructions for Windows, Mac, and Linux.

## What Makes This Tool Useful

- **Automatic Analysis**: Upload your PGN files and the tool automatically identifies critical moments using Stockfish engine analysis
- **Interactive Learning**: Practice finding better moves at critical positions - the tool evaluates your alternative moves in real-time
- **Simple Workflow**: No complex setup required - just upload a PGN and start learning
- **Visual Feedback**: Navigate through games move-by-move with a clear, intuitive chessboard interface
- **Focus on Mistakes**: Jump directly to critical moments where mistakes were made, so you can focus your study time effectively
- **All Local**: Your analysis is yours, not using external resources and visible to you

The tool is intended for beginning or intermediate players. Unlike the "game review" functions available on online platforms, it

- highlights fewer mistakes, usually only the ones that really make a difference
- never shows an engine evaluation (this is often a distraction)
- allows good moves even if not the top engine choice (though lichess does this too)

## What You Might Miss

- **No Positive Feedback**: this tool won't tell you if you made a brilliant sacrifice or found a cunning tactic
- **No Nuance**: if you slowly get ground down in a positional slugfest, this tool won't tell you where you went wrong

## Installation Options

### Docker

If you have Docker installed, this is the simplest option:

```bash
docker-compose up
```

Then open http://localhost:9292 in your browser. Your games are automatically saved in the `games` folder.

Don't have Docker?  See the [Quickstart Guide](QUICKSTART.md).

### Alternative: Native Installation

For detailed installation instructions including native installation (without Docker), see [INSTALL.md](INSTALL.md).

## Usage

### Uploading and Analyzing Games

1. Get a PGN of your game (most online chess sites allow you to export via copy/paste)
2. Paste the PGN content into the upload form on the home page
3. Click "Analyze Game" - the tool will:
   - Analyze the game with Stockfish
   - Identify critical moments (blunders/mistakes)
   - Save the annotated PGN file
   - Provide a link to view the completed analysis

### Playing Through a Game

- **Navigate moves**: Use the forward/backward buttons to move through the game
- **Jump to critical moments**: Use the "Next Critical Moment" button to skip directly to positions where mistakes were made
- **Practice finding better moves**: When at a critical moment, try to find a better move - the tool will evaluate your suggestion using Stockfish
- **Learn from mistakes**: Study the correct moves and understand why your original move was suboptimal

Critical moments are automatically annotated with `$201` (SCID's standard annotation for critical positions).

### To Get the Most of Your Analysis

Do it soon after the game so your memory is still fresh. When you reach a move where you made a mistake, remember your thinking process. Did you understand what your opponent was trying to do? Did you understand where your position had weaknesses? Did you understand what you should be trying for in the position? If you had a time machine, what could you have done differently to avoid the mistake? How can you adjust your thinking to avoid it in future?

Given all the mistakes that can be made it takes a long time to fix all of them. But if you notice patterns that can really help.

## Security Warning

⚠️ **Important**: This application is designed for local use and is not hardened for public internet exposure. Do not run this tool on a server that is directly accessible from the internet without proper security measures (firewall rules, authentication, HTTPS, etc.). The application does not include authentication or rate limiting and may be vulnerable to various attacks if exposed publicly.

For local development and personal use on your own machine, it's safe. If you need to deploy it, ensure you:
- Run it behind a reverse proxy with authentication
- Use HTTPS
- Restrict access with firewall rules
- Review and implement additional security measures as needed

## Development

### Running Tests

The test suite is split into unit tests and integration tests. Unit tests don't require external dependencies, while integration tests require Stockfish to be installed and available.

**Unit Tests** (default, no Stockfish required):
```bash
bundle exec rake test
# Or run a specific test file:
bundle exec ruby -Itest test/game_editor_test.rb
```

**Integration Tests** (requires Stockfish):
```bash
bundle exec rake integration
# Or run a specific integration test file:
bundle exec ruby -Itest test/integration/game_editor_integration_test.rb
```

**JavaScript tests:**
```bash
npm test
# Or run once (non-watch mode):
npm run test_once
```

**Note:** The default `rake test` task automatically excludes integration tests. Integration tests that require Stockfish are located in `test/integration/` and must be run separately.

### Code Linting

Ruby:
```bash
bundle exec rubocop
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Implementation Notes

- The backend is built with Ruby/Sinatra
- The frontend uses vanilla JavaScript (no framework)
- [cm-chessboard](https://github.com/shaack/cm-chessboard) (MIT License) is used for the chessboard UI
- [chess.js](https://github.com/jhlywa/chess.js) (BSD-2-Clause License) is used for the chess logic
- Game analysis is performed using the Stockfish engine via the `stockfish` Ruby gem
- PGN parsing is handled by the `pgn2` gem

