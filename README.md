# Chess Learner Tool

A web-based chess learning tool that helps you learn from your games by automatically identifying critical moments (blunders and mistakes) and allowing you to practice finding better moves. This tool integrates with Stockfish to analyze your games and provides an interactive interface for studying your play.

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

## Prerequisites

Before you begin, ensure you have the following installed:

- **Ruby** (version 3.2.3 or higher recommended)
- **Bundler** gem (`gem install bundler`)
- **npm** (Node.js package manager)
- **Stockfish** (Install via your system package manager, e.g., `apt-get install stockfish` on Debian/Ubuntu, `brew install stockfish` on macOS.)

## Installation

1. Clone this repository:
   ```bash
   git clone <repository-url>
   cd learner
   ```

2. Install Ruby dependencies:
   ```bash
   bundle install
   ```

3. Install JavaScript dependencies:
   ```bash
   npm install
   ```

4. Copy third-party assets (chessboard components):
   ```bash
   npm run copy-all
   ```

## Running Locally

1. Set up a directory for your PGN files. You can use the test data directory for testing:
   ```bash
   # Option 1: Use the existing test data directory
   export PGN_DIR=./test/data
   
   # Option 2: Create your own directory
   mkdir -p ~/chess-games
   export PGN_DIR=~/chess-games
   ```

2. Start the server:
   ```bash
   bundle exec puma config.ru
   ```

   The server will start on `http://localhost:9292` by default (or the port configured by Puma).

3. Open your web browser and navigate to:
   ```
   http://localhost:9292
   ```

4. Upload a PGN file:
   - Paste your PGN content into the text area, or
   - The tool will analyze it automatically and identify critical moments
   - Once analysis is complete, click the link to view your analyzed game

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
bundle exec rake test:integration
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

### Fixing Stockfish Gem Warning

The stockfish gem (version 0.3.1) generates a frozen string literal warning in Ruby 3.4+. To silence this warning, you can run the fix script:

```bash
ruby scripts/fix_stockfish_warning.rb
```

This script will:
- Find the stockfish gem installation (works regardless of gem location)
- Show a preview of the changes
- Ask for your permission before modifying the gem file
- Create a backup of the original file
- Add `# frozen_string_literal: true` at the top of the gem file
- Fix mutable string issues (e.g., `output = ""` → `output = String.new`) that would cause test failures

**Note:** This modifies the gem file in place. If you reinstall the gem, you'll need to run this script again. The script fixes both the warning and the test failures caused by frozen strings.

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

