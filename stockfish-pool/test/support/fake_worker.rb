# frozen_string_literal: true

# In-memory stand-in for EngineWorker, used to test the pool and the HTTP layer
# without engine processes.
class FakeWorker
  @registry = []

  class << self
    attr_reader :registry
  end

  attr_reader :searches
  attr_accessor :healthy, :gate, :failure

  def initialize(fail_start: false)
    @fail_start = fail_start
    @alive = false
    @healthy = true
    @searches = []
    self.class.registry << self
  end

  def start
    raise StockfishPool::WorkerCrashed, 'fake start failure' if @fail_start

    @alive = true
    self
  end

  def alive?
    @alive
  end

  def responsive?(_timeout = nil)
    @alive && @healthy
  end

  # Blocks on +gate+ (a Queue) when one is set, so tests control timing.
  def search(request)
    @searches << request
    gate&.pop
    if failure
      @alive = false
      raise failure
    end
    { bestmove: 'e2e4', lines: [{ multipv: 1, move: 'e2e4', score: { cp: 20 }, depth: 12, pv: %w[e2e4] }],
      engine: 'FakeWorker' }
  end

  def kill
    @alive = false
  end

  def stop
    @alive = false
  end
end
