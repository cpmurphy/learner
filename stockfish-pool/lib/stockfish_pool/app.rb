# frozen_string_literal: true

require 'json'
require 'rack/utils'
require 'sinatra/base'
require_relative 'search_request'
require_relative 'service'

module StockfishPool
  # HTTP/JSON front end. Callers authenticate with a bearer token and send a
  # structured search; they never send UCI text.
  class App < Sinatra::Base
    MAX_BODY_BYTES = 16 * 1024

    set :show_exceptions, false
    set :raise_errors, false
    set :dump_errors, false
    set :host_authorization, { permitted_hosts: [] }

    def initialize(app = nil, service:, **kwargs)
      super(app, **kwargs)
      @service = service
      @request_builder = RequestBuilder.new(service.config)
    end

    before '/v1/*' do
      content_type :json
      halt_json(401, 'unauthorized', 'Missing or invalid bearer token') unless authorized?
    end

    get '/healthz' do
      content_type :json
      health = @service.health
      status(health[:status] == 'down' ? 503 : 200)
      health.to_json
    end

    post '/v1/analyze' do
      search = @request_builder.build(read_json_body)
      @service.analyze(search).to_json
    end

    error InvalidRequest do
      error_json(422, 'invalid_request', env['sinatra.error'].message)
    end

    error QuotaExceeded, Busy do
      error = env['sinatra.error']
      headers 'Retry-After' => error.retry_after.to_s
      code = error.is_a?(QuotaExceeded) ? 'quota_exceeded' : 'busy'
      error_json(429, code, error.message)
    end

    error Unavailable, WorkerError do
      headers 'Retry-After' => '1'
      error_json(503, 'engine_unavailable', env['sinatra.error'].message)
    end

    not_found do
      content_type :json
      { error: 'not_found' }.to_json
    end

    error do
      error_json(500, 'internal_error', 'Internal error')
    end

    private

    def authorized?
      header = request.env['HTTP_AUTHORIZATION'].to_s
      return false unless header.start_with?('Bearer ')

      presented = header.delete_prefix('Bearer ')
      # Compare against every token so timing does not reveal which one matched.
      settings_tokens.map { |token| Rack::Utils.secure_compare(token, presented) }.any?
    end

    def settings_tokens
      @service.config.tokens
    end

    # Requiring a JSON media type also keeps Rack from consuming the body as form data.
    def read_json_body
      unless request.media_type == 'application/json'
        halt_json(415, 'unsupported_media_type', 'Content-Type must be application/json')
      end
      body = request.body.read(MAX_BODY_BYTES + 1).to_s
      if body.bytesize > MAX_BODY_BYTES
        halt_json(413, 'payload_too_large', "Body must be at most #{MAX_BODY_BYTES} bytes")
      end
      JSON.parse(body, max_nesting: 4)
    rescue JSON::ParserError # includes JSON::NestingError
      halt_json(400, 'invalid_json', 'Body must be valid JSON')
    end

    def halt_json(code, error, message)
      halt code, { 'Content-Type' => 'application/json' }, { error: error, message: message }.to_json
    end

    def error_json(code, error, message)
      content_type :json
      status code
      { error: error, message: message }.to_json
    end
  end
end
