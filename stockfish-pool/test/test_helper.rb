# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'minitest/autorun'
require 'rbconfig'
require 'logger'
require 'stockfish_pool'

module TestSupport
  FAKE_ENGINE = File.expand_path('support/fake_engine.rb', __dir__)
  START_FEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
  TOKEN = 'test-token-0123456789abcdef'
  BASE_ENV = {
    'API_TOKENS' => TOKEN,
    'STOP_GRACE_MS' => '50',
    'KILL_GRACE_MS' => '200',
    'INTERACTIVE_MAX_MOVETIME_MS' => '100',
    'BATCH_MAX_MOVETIME_MS' => '100'
  }.freeze

  module_function

  def config(overrides = {}, engine_mode: 'normal', log: nil)
    command = [RbConfig.ruby, FAKE_ENGINE, engine_mode, log].compact
    StockfishPool::Config.new(BASE_ENV.merge(overrides), engine_command: command)
  end

  def request(config, params = {})
    StockfishPool::RequestBuilder.new(config).build({ 'fen' => START_FEN }.merge(params))
  end

  def null_logger
    Logger.new(File::NULL)
  end
end
