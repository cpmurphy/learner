# frozen_string_literal: true

source 'https://rubygems.org'

gem 'json' # Standard JSON library, Sinatra often includes it
gem 'pgn2'
gem 'puma', '>= 5.0' # A recommended server for Sinatra
# pgn2 requires racc/parser without declaring it; since Ruby 3.4 racc is a bundled
# (not default) gem, so production bundles without dev gems need it listed.
gem 'racc'
gem 'rack-attack'       # Per-IP rate limits for the public site
gem 'sinatra', '>= 3.2' # Using a recent stable version
# Client for the stockfish-pool engine service (used when ENGINE_URL is set).
# Keep this tag equal to POOL_REF (bin/check-pool-ref enforces it). For local
# client work, point Bundler at the repository root (not client/); a tag pin
# also needs the branch check turned off:
#   bundle config set local.stockfish_pool_client /path/to/stockfish-pool
#   bundle config set disable_local_branch_check true
# Undo with `bundle config unset` on both settings.
gem 'stockfish_pool_client',
    git: 'https://github.com/cpmurphy/stockfish-pool.git',
    glob: 'client/*.gemspec',
    tag: 'v0.1.0'

group :development, :test do
  gem 'debug', '>= 1.0.0'
  gem 'minitest'
  gem 'minitest-mock'
  gem 'rack-test'
  gem 'rubocop', require: false
  gem 'rubocop-minitest', require: false
  gem 'simplecov', require: false
end

gem 'rake', '~> 13.4'
