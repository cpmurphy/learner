# frozen_string_literal: true

require 'open3'

# A lightweight UCI (Universal Chess Interface) engine wrapper for Stockfish.
# This class handles communication with the Stockfish chess engine using the UCI protocol.
#
# It provides a minimal interface that supports the needs of this application without
# attempting to implement the full UCI specification.
class StockfishEngine
  class EngineError < StandardError; end
  class CommunicationError < EngineError; end

  def initialize(engine_path = 'stockfish')
    @engine_path = engine_path
    @stdin = nil
    @stdout = nil
    @stderr = nil
    @wait_thread = nil
    start_engine
  end

  # Execute a UCI command and return the output.
  # This is the main method for sending commands to the engine.
  #
  # @param command [String] The UCI command to execute
  # @return [String] The output from the engine
  def execute(command)
    raise CommunicationError, 'Engine not running' unless running?

    send_command(command)

    # For commands that expect a response, read until we get the appropriate terminator
    case command
    when /^go /
      read_until_bestmove
    else
      # For other commands (quit, setoption, position, etc.), just return empty string
      # These commands don't produce output we need to capture
      ''
    end
  rescue Errno::EPIPE, IOError => e
    raise CommunicationError, "Failed to communicate with engine: #{e.message}"
  end

  # Analyze a position and return the full output.
  # This method sends position and go commands, then collects all analysis output.
  #
  # @param fen [String] The FEN string of the position to analyze
  # @param depth [Integer] The depth to analyze to
  # @return [String] The complete analysis output from the engine
  def analyze(fen, depth:)
    raise CommunicationError, 'Engine not running' unless running?

    send_command("position fen #{fen}")
    send_command("go depth #{depth}")
    read_until_bestmove
  rescue Errno::EPIPE, IOError => e
    raise CommunicationError, "Failed to analyze position: #{e.message}"
  end

  # Set the MultiPV option for the engine.
  # MultiPV tells the engine to output multiple best move variations.
  #
  # @param value [Integer] Number of variations to calculate
  def multipv(value)
    execute("setoption name MultiPV value #{value}")
  end

  # Check if the engine process is still running.
  #
  # @return [Boolean] true if the engine is running
  def running?
    return false unless @wait_thread

    @wait_thread.alive?
  end

  # Close the engine and clean up resources.
  def close
    return unless running?

    begin
      execute('quit')
    rescue CommunicationError
      # Ignore errors on quit - the engine might already be closed
    end

    # Give the engine a moment to exit gracefully
    sleep 0.1 unless @wait_thread.join(0.5)

    # Force kill if still running
    if @wait_thread.alive?
      begin
        Process.kill('TERM', @wait_thread.pid)
      rescue StandardError
        nil
      end
      @wait_thread.join(0.5)
    end

    cleanup_io
  end

  private

  def start_engine
    @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(@engine_path)

    # Set IO to non-blocking mode for better error handling
    @stdin.sync = true
    @stdout.sync = true

    # Initialize UCI mode
    send_command('uci')
    wait_for_uciok

    # Send isready to ensure engine is ready for commands
    send_command('isready')
    wait_for_readyok
  rescue Errno::ENOENT
    raise EngineError, "Stockfish engine not found at: #{@engine_path}"
  rescue StandardError => e
    cleanup_io
    raise EngineError, "Failed to start engine: #{e.message}"
  end

  def send_command(command)
    @stdin.puts(command)
  end

  def wait_for_uciok
    loop do
      line = read_line_with_timeout
      return if line&.start_with?('uciok')
    end
  end

  def wait_for_readyok
    loop do
      line = read_line_with_timeout
      return if line&.start_with?('readyok')
    end
  end

  def read_until_bestmove
    output = String.new
    loop do
      line = read_line_with_timeout
      break unless line

      output << line << "\n"
      break if line.start_with?('bestmove')
    end
    output
  end

  def read_line_with_timeout(timeout = 30)
    # Use wait_readable to implement timeout (fiber scheduler compatible)
    return nil unless @stdout.wait_readable(timeout)

    @stdout.gets&.chomp
  rescue IOError
    nil
  end

  def cleanup_io
    [@stdin, @stdout, @stderr].each do |io|
      io&.close
    rescue StandardError
      nil
    end
    @stdin = nil
    @stdout = nil
    @stderr = nil
    @wait_thread = nil
  end
end
