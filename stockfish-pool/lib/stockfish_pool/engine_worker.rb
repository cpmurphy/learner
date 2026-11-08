# frozen_string_literal: true

require_relative 'uci_process'
require_relative 'info_parser'

module StockfishPool
  class WorkerError < StandardError; end
  # The engine overran its time limit and had to be killed.
  class SearchTimeout < WorkerError; end
  # The engine process died or stopped responding.
  class WorkerCrashed < WorkerError; end

  # Owns one engine process and runs searches on it. Every UCI command is built
  # here from a validated SearchRequest; callers never supply command text.
  #
  # Each search starts with "ucinewgame" so no state (hash contents, history)
  # carries over from one caller to the next.
  class EngineWorker
    HANDSHAKE_TIMEOUT_S = 10
    READY_TIMEOUT_S = 2

    attr_reader :engine_name

    def initialize(config:, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
                   process_factory: ->(command) { UciProcess.new(command) },
                   handshake_timeout_s: HANDSHAKE_TIMEOUT_S)
      @config = config
      @clock = clock
      @handshake_timeout_s = handshake_timeout_s
      @process_factory = process_factory
      @multipv = nil
    end

    def start
      @process = @process_factory.call(@config.engine_command)
      handshake
      self
    rescue UciProcess::Error => e
      stop
      raise WorkerCrashed, "Engine failed to start: #{e.message}"
    end

    def alive?
      !@process.nil? && @process.alive?
    end

    # Health check: true if the engine answers "isready" in time.
    def responsive?(timeout_s = READY_TIMEOUT_S)
      return false unless alive?

      @process.write_line('isready')
      @process.read_until('readyok', @clock.call + timeout_s)
    rescue UciProcess::Error
      false
    end

    def search(request)
      raise WorkerCrashed, 'Engine is not running' unless alive?

      prepare(request)
      output = run_go(request)
      InfoParser.parse(output).merge(engine: engine_name)
    rescue UciProcess::Error => e
      kill
      raise WorkerCrashed, "Engine failed during search: #{e.message}"
    end

    def stop
      @process&.quit
    ensure
      @process = nil
    end

    def kill
      @process&.kill
    ensure
      @process = nil
    end

    private

    def handshake
      lines = []
      send_and_wait('uci', 'uciok', @handshake_timeout_s, lines)
      @engine_name = lines.find { |line| line.start_with?('id name ') }&.delete_prefix('id name ')
      @process.write_line("setoption name Threads value #{@config.threads}")
      @process.write_line("setoption name Hash value #{@config.hash_mb}")
      send_and_wait('isready', 'readyok', @handshake_timeout_s)
    end

    def prepare(request)
      @process.write_line('ucinewgame')
      if @multipv != request.multipv
        @process.write_line("setoption name MultiPV value #{request.multipv}")
        @multipv = request.multipv
      end
      send_and_wait('isready', 'readyok', READY_TIMEOUT_S)
      @process.write_line(position_command(request))
    end

    def position_command(request)
      command = "position fen #{request.fen}"
      command += " moves #{request.moves.join(' ')}" unless request.moves.empty?
      command
    end

    # Stockfish honours movetime itself; the deadlines below only matter when
    # it does not. Past the limit we send "stop", and if even that is ignored
    # the process is killed.
    def run_go(request)
      @process.write_line("go depth #{request.depth} movetime #{request.movetime_ms} nodes #{request.nodes}")
      output = []
      deadline = @clock.call + ((request.movetime_ms + @config.stop_grace_ms) / 1000.0)
      return output if @process.read_until('bestmove', deadline, output)

      @process.write_line('stop')
      return output if @process.read_until('bestmove', @clock.call + (@config.kill_grace_ms / 1000.0), output)

      kill
      raise SearchTimeout, 'Engine ignored stop and was killed'
    end

    def send_and_wait(command, reply, timeout_s, lines = [])
      @process.write_line(command)
      return if @process.read_until(reply, @clock.call + timeout_s, lines)

      raise UciProcess::Error, "No #{reply} within #{timeout_s}s"
    end
  end
end
