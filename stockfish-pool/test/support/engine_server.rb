# frozen_string_literal: true

require 'json'
require 'logger'
require 'net/http'
require 'puma'
require 'puma/log_writer'
require 'puma/server'

# The real service (StockfishPool::App, Service, Pool and EngineWorkers
# driving real Stockfish processes) behind an in-process Puma server, called
# over HTTP. Shared by the property tests and shut down when the run ends.
class EngineServer
  ENGINE = ENV.fetch('ENGINE_PATH') do
    ENV['PATH'].split(File::PATH_SEPARATOR).map { |dir| File.join(dir, 'stockfish') }.find { |p| File.executable?(p) }
  end

  TOKEN = 'property-token-0123456789abcdef'

  # Searches are bounded by depth, never by time, so that results are
  # deterministic (one thread, and every search starts with "ucinewgame").
  # Queues and budgets are big enough that load never causes a 429.
  SETTINGS = {
    'API_TOKENS' => TOKEN,
    'POOL_SIZE' => '3',
    'RESERVED_INTERACTIVE' => '1',
    'THREADS' => '1',
    'HASH_MB' => '16',
    'INTERACTIVE_MAX_DEPTH' => '20',
    'BATCH_MAX_DEPTH' => '20',
    'INTERACTIVE_MAX_MOVETIME_MS' => '20000',
    'BATCH_MAX_MOVETIME_MS' => '20000',
    'INTERACTIVE_MAX_NODES' => '10000000',
    'BATCH_MAX_NODES' => '10000000',
    'INTERACTIVE_QUEUE_MAX' => '200',
    'BATCH_QUEUE_MAX' => '200',
    'INTERACTIVE_QUEUE_WAIT_S' => '120',
    'BATCH_QUEUE_WAIT_S' => '120',
    'GLOBAL_ENGINE_SEC_PER_MIN' => '100000'
  }.freeze

  PUMA_THREADS = 32

  Response = Struct.new(:status, :body, keyword_init: true) do
    # The parts of a 200 response that depend only on the search, not on timing.
    def analysis
      body.slice('bestmove', 'lines', 'engine', 'lane', 'applied')
    end
  end

  def self.shared
    @shared ||= new.tap { |server| Minitest.after_run { server.stop } }
  end

  attr_reader :service

  def initialize
    config = StockfishPool::Config.new(SETTINGS, engine_command: [ENGINE])
    @service = StockfishPool::Service.build(config, logger: Logger.new(File::NULL)).start
    @server = Puma::Server.new(StockfishPool::App.new(service: @service), nil,
                               min_threads: 1, max_threads: PUMA_THREADS, log_writer: Puma::LogWriter.null)
    @port = @server.add_tcp_listener('127.0.0.1', 0).addr[1]
    @server.run
  end

  def analyze(params)
    http do |connection|
      response = connection.post('/v1/analyze', params.to_json,
                                 'Authorization' => "Bearer #{TOKEN}", 'Content-Type' => 'application/json')
      Response.new(status: response.code.to_i, body: JSON.parse(response.body))
    end
  end

  # Sends every request at once, each from its own thread; results are in request order.
  def analyze_concurrently(requests)
    requests.map { |params| Thread.new { analyze(params) } }.map(&:value)
  end

  def health
    http { |connection| JSON.parse(connection.get('/healthz').body) }
  end

  def stop
    @server.stop(true)
    @service.shutdown
  end

  private

  def http(&block)
    Net::HTTP.start('127.0.0.1', @port, open_timeout: 5, read_timeout: 120, &block)
  end
end
