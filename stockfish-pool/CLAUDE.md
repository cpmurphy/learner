# stockfish-pool/

`stockfish-pool/` is a self-contained HTTP/JSON service (own Gemfile, tests and `.rubocop.yml`) that runs a fixed, sandboxable pool of Stockfish engines. `stockfish-pool/client/` is its client gem, which the app uses as a path gem. Run its tests with `cd stockfish-pool && bundle exec rake test`. CI lints it with the root config (`bin/rubocop` forces it), so test exclusions for `stockfish-pool/test` belong in the root `.rubocop.yml` as well as this directory's `.rubocop.yml`.
