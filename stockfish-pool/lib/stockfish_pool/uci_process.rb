# frozen_string_literal: true

require 'open3'
require 'io/wait'

module StockfishPool
  # A single engine process speaking UCI over pipes. Reads are always bounded by
  # a deadline, and the process runs in its own process group so it can be
  # killed outright if it misbehaves.
  class UciProcess
    class Error < StandardError; end

    MAX_BUFFER = 1024 * 1024
    READ_CHUNK = 64 * 1024

    attr_reader :pid

    def initialize(command, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @clock = clock
      @buffer = String.new
      @stdin, @stdout, @wait_thread = Open3.popen2(*Array(command), pgroup: true)
      @pid = @wait_thread.pid
    rescue SystemCallError => e
      raise Error, "Failed to start engine: #{e.message}"
    end

    def write_line(line)
      raise ArgumentError, 'UCI command must not contain line breaks' if line.match?(/[\r\n]/)

      @stdin.write("#{line}\n")
      @stdin.flush
    rescue IOError, SystemCallError => e
      raise Error, "Engine write failed: #{e.message}"
    end

    # Reads lines until one starts with +prefix+, appending every line read to
    # +lines+. Returns true when the prefix line was read, false on timeout.
    def read_until(prefix, deadline, lines = [])
      loop do
        line = read_line(deadline)
        return false if line.nil?

        lines << line
        return true if line.start_with?(prefix)
      end
    end

    # Returns the next line, or nil if +deadline+ passes first.
    def read_line(deadline)
      loop do
        newline = @buffer.index("\n")
        return @buffer.slice!(0..newline).chomp if newline

        remaining = deadline - @clock.call
        return nil if remaining <= 0
        return nil unless @stdout.wait_readable(remaining)

        fill_buffer
      end
    end

    def alive?
      @wait_thread.alive?
    end

    def kill
      signal_group('KILL')
      @wait_thread.join(1)
    ensure
      close_pipes
    end

    def quit
      write_line('quit') if alive?
    rescue Error
      nil
    ensure
      kill unless @wait_thread.join(0.5)
      close_pipes
    end

    private

    def fill_buffer
      chunk = @stdout.read_nonblock(READ_CHUNK, exception: false)
      return if chunk == :wait_readable
      raise Error, 'Engine closed its output' if chunk.nil?

      @buffer << chunk
      raise Error, 'Engine output line too long' if @buffer.bytesize > MAX_BUFFER
    rescue IOError, SystemCallError => e
      raise Error, "Engine read failed: #{e.message}"
    end

    def signal_group(signal)
      Process.kill(signal, -@pid)
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end

    def close_pipes
      [@stdin, @stdout].each do |io|
        io.close unless io.closed?
      rescue IOError
        nil
      end
    end
  end
end
