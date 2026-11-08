# frozen_string_literal: true

require_relative 'stockfish_pool/config'
require_relative 'stockfish_pool/input_validator'
require_relative 'stockfish_pool/search_request'
require_relative 'stockfish_pool/info_parser'
require_relative 'stockfish_pool/uci_process'
require_relative 'stockfish_pool/engine_worker'
require_relative 'stockfish_pool/budgets'
require_relative 'stockfish_pool/pool'
require_relative 'stockfish_pool/service'
require_relative 'stockfish_pool/app'

# A sandboxable pool of Stockfish engines behind a small HTTP/JSON API.
module StockfishPool
  VERSION = '0.1.0'
end
