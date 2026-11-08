# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require_relative 'client/version'

module StockfishPool
  # Calls a stockfish-pool service. Thread-safe: each call opens its own
  # connection. Only the standard library is used.
  #
  #   client = StockfishPool::Client.new(url: 'http://stockfish-pool:4000', token: ENV.fetch('ENGINE_TOKEN'))
  #   result = client.analyze(fen: fen, multipv: 3)
  #   result.lines.first.move        # => "e2e4"
  #   result.lines.first.score.cp    # => 34 (side to move's point of view)
  class Client
    class Error < StandardError; end
    # The token was missing or rejected.
    class Unauthorized < Error; end
    # The service rejected the request's content (FEN, moves, limits...).
    class InvalidRequest < Error; end
    # The service answered something this client does not understand.
    class ProtocolError < Error; end

    # Errors that may succeed later. +retry_after+ is in seconds, when known.
    class RetryableError < Error
      attr_reader :retry_after

      def initialize(message = nil, retry_after: nil)
        super(message)
        @retry_after = retry_after
      end
    end

    # The pool's queue is full, the wait timed out, or the global budget is used up.
    class Busy < RetryableError; end
    # The caller's subject has used up its engine time.
    class QuotaExceeded < RetryableError; end
    # The service is unreachable, has no healthy engine, or the engine failed.
    class Unavailable < RetryableError; end

    Score = Struct.new(:cp, :mate, keyword_init: true) do
      def mate?
        !mate.nil?
      end
    end
    Line = Struct.new(:multipv, :move, :score, :depth, :pv, keyword_init: true)
    Result = Struct.new(:bestmove, :lines, :engine, :lane, :applied, :ms, keyword_init: true)

    # Failures before the request reached the service: always safe to retry.
    CONNECT_ERRORS = [Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::EADDRNOTAVAIL,
                      Net::OpenTimeout, SocketError].freeze
    # Failures after the request may have reached it: not retried, since the
    # search may still be using the engine.
    TRANSPORT_ERRORS = [Errno::ECONNRESET, Errno::EPIPE, Net::ReadTimeout, Net::WriteTimeout,
                        EOFError, IOError].freeze

    # rubocop:disable Metrics/ParameterLists
    def initialize(url:, token:, open_timeout: 2, read_timeout: 40, retries: 1, retry_delay: 0.5)
      # rubocop:enable Metrics/ParameterLists
      @uri = URI(url)
      raise ArgumentError, "Unsupported URL: #{url}" unless %w[http https].include?(@uri.scheme)
      raise ArgumentError, 'token is required' if token.to_s.empty?

      @token = token
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @retries = retries
      @retry_delay = retry_delay
    end

    # Runs a search. Only +fen+ is required; limits that are omitted use the
    # service's lane defaults, and limits that are too high are clamped (see
    # +Result#applied+).
    #
    # @return [Result]
    # rubocop:disable Metrics/ParameterLists
    def analyze(fen:, moves: [], lane: :interactive, depth: nil, multipv: nil, movetime_ms: nil, nodes: nil,
                subject: nil)
      # rubocop:enable Metrics/ParameterLists
      body = { fen: fen, moves: moves, lane: lane.to_s, depth: depth, multipv: multipv,
               movetime_ms: movetime_ms, nodes: nodes, subject: subject }.compact
      build_result(with_retries { request(Net::HTTP::Post, '/v1/analyze', body) })
    end

    # @return [Hash] the service's /healthz document
    def health
      with_retries { request(Net::HTTP::Get, '/healthz', nil, allow: [200, 503]) }
    end

    private

    def with_retries
      attempts = 0
      begin
        attempts += 1
        yield
      rescue Unavailable
        raise if attempts > @retries

        sleep @retry_delay
        retry
      end
    end

    def request(verb, path, body, allow: [200])
      response = perform(build_request(verb, path, body))
      return parse_json(response.body) if allow.include?(response.code.to_i)

      raise error_for(response)
    end

    def build_request(verb, path, body)
      request = verb.new(@uri.request_uri.chomp('/') + path)
      request['Authorization'] = "Bearer #{@token}"
      request['Accept'] = 'application/json'
      if body
        request['Content-Type'] = 'application/json'
        request.body = JSON.generate(body)
      end
      request
    end

    def perform(request)
      Net::HTTP.start(@uri.host, @uri.port, use_ssl: @uri.scheme == 'https',
                                            open_timeout: @open_timeout, read_timeout: @read_timeout) do |http|
        http.request(request)
      end
    rescue *CONNECT_ERRORS => e
      raise Unavailable, "Cannot reach engine service: #{e.class}: #{e.message}"
    rescue *TRANSPORT_ERRORS => e
      raise Error, "Engine service connection failed: #{e.class}: #{e.message}"
    end

    def error_for(response)
      payload = parse_json(response.body, strict: false)
      message = payload['message'] || "HTTP #{response.code}"
      retry_after = response['Retry-After']&.to_i
      case response.code.to_i
      when 401 then Unauthorized.new(message)
      when 400, 413, 415, 422 then InvalidRequest.new(message)
      when 429 then rate_limit_error(payload['error'], message, retry_after)
      when 503 then Unavailable.new(message, retry_after: retry_after)
      else ProtocolError.new("Unexpected HTTP #{response.code}: #{message}")
      end
    end

    def rate_limit_error(code, message, retry_after)
      klass = code == 'quota_exceeded' ? QuotaExceeded : Busy
      klass.new(message, retry_after: retry_after)
    end

    def parse_json(text, strict: true)
      JSON.parse(text.to_s)
    rescue JSON::ParserError
      raise ProtocolError, 'Engine service returned invalid JSON' if strict

      {}
    end

    def build_result(data)
      Result.new(
        bestmove: data['bestmove'],
        lines: Array(data['lines']).map { |line| build_line(line) },
        engine: data['engine'],
        lane: data['lane']&.to_sym,
        applied: (data['applied'] || {}).transform_keys(&:to_sym),
        ms: data['ms']
      )
    rescue NoMethodError, TypeError => e
      raise ProtocolError, "Unexpected response shape: #{e.message}"
    end

    def build_line(line)
      score = line.fetch('score')
      Line.new(multipv: line['multipv'], move: line['move'], depth: line['depth'], pv: Array(line['pv']),
               score: Score.new(cp: score['cp'], mate: score['mate']))
    rescue KeyError => e
      raise ProtocolError, "Unexpected response shape: #{e.message}"
    end
  end
end
