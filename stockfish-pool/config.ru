# frozen_string_literal: true

require_relative 'lib/stockfish_pool'

$stdout.sync = true
config = StockfishPool::Config.from_env
warn 'stockfish-pool: API_TOKENS is empty; every /v1 request will be rejected' if config.tokens.empty?

service = StockfishPool::Service.build(config).start
at_exit { service.shutdown }

run StockfishPool::App.new(service: service)
