# Development

## Running Tests

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

## Code Linting

Ruby:
```bash
bundle exec rubocop
```

## Updating stockfish-pool

The engine service lives in the separate [stockfish-pool](https://github.com/cpmurphy/stockfish-pool) repo. This app pins it in three places that must stay in sync:

- `POOL_REF` — tag used to build the pool image and to sync chess rules
- the `stockfish_pool_client` gem tag in the Gemfile
- the locked tag in `Gemfile.lock`

`bin/check-pool-ref` enforces that agreement in CI, deploys, image builds, and the local pre-commit hook. Chess rules under `lib/chess_rules/` are copied from the pool with `bin/sync-chess-rules`.

To bump to a new pool release (after the tag exists on GitHub):

```bash
bin/bump-pool-ref.sh v0.1.2
```

That script:

1. Checks out a `bump-pool-ref` branch from up-to-date `main`
2. Sets `POOL_REF` and the Gemfile tag, runs `bundle install`, and syncs chess rules
3. Runs `bin/check-pool-ref`
4. Commits, force-pushes the branch with `--force-with-lease`, and opens (or reuses) a PR

You can omit the tag argument: if `POOL_REF` already differs from the Gemfile pin, that value is used; otherwise the script prompts (or exits with usage when not on a TTY).

The working tree must be clean except for an edited `POOL_REF` (and this script itself when adding it). Re-running with the same tag recreates the local `bump-pool-ref` branch from `main` and updates the PR.

For local client edits without bumping the pin, point Bundler at a checkout:

```bash
bundle config set local.stockfish_pool_client /path/to/stockfish-pool
bundle config set disable_local_branch_check true
```

Use the stockfish-pool repository root, not `client/`. The Gemfile pins a tag, so the branch check must be disabled.
