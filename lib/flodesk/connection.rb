# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Flodesk
  # Executes HTTP requests against the Flodesk API.
  #
  # A Connection holds no per-request mutable state, so one instance is safe to
  # share across threads. Each request opens its own `Net::HTTP` session rather
  # than reusing a socket: simple, and correct under concurrency. Connection
  # pooling is a possible later optimization, not a v1 requirement.
  class Connection
    # Exceptions Net::HTTP raises when a request never completed.
    TIMEOUT_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout].freeze

    CONNECTION_ERRORS = [
      EOFError, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
      Errno::ENETUNREACH, IOError, SocketError
    ].freeze

    def initialize(client)
      @client = client
      freeze
    end

    # Issues a request and returns a Response, retrying per the retry policy.
    #
    # `idempotent` declares whether repeating this operation is safe.
    #
    # For POST it must be stated explicitly and defaults to false, because in
    # this API retry safety is a property of the endpoint rather than the verb:
    # POST /subscribers and POST /subscribers/batch are upserts and safe to
    # repeat, while POST /segments, POST /custom-fields, POST /webhooks and
    # POST /campaigns/canva all create, so repeating them duplicates a record or
    # sends a campaign twice. Assuming POST is retryable is the single most
    # damaging mistake a client of this API can make.
    #
    # GET, PUT and DELETE are idempotent by HTTP definition and default to true.
    def request(method, path, query: nil, body: nil, idempotent: nil, retry_rate_limit: true)
      policy = RetryPolicy.new(
        idempotent: idempotent.nil? ? method != :post : idempotent,
        retry_rate_limit: retry_rate_limit,
        max_retries: @client.max_retries
      )
      attempt = 0

      loop do
        attempt += 1
        error = attempt_once(method, path, query, body, attempt) { |response| return response }

        raise error unless policy.retry?(error, attempt)

        backoff(attempt)
      end
    end

    private

    # Yields the response to the caller's block on success. Returns the error to
    # weigh for retry on failure, rather than raising, so the retry decision is
    # made in one place.
    def attempt_once(method, path, query, body, attempt)
      response = execute(method, path, query, body, attempt)
      if response.status < 400
        yield response
        return nil
      end

      Error.from_response(
        status: response.status, body: response.body, headers: response.headers
      )
    rescue *TIMEOUT_ERRORS => e
      TimeoutError.new("#{method.to_s.upcase} #{Redaction.path(path)} timed out (#{e.class})")
    rescue *CONNECTION_ERRORS => e
      ConnectionError.new("#{method.to_s.upcase} #{Redaction.path(path)} failed (#{e.class})")
    end

    def execute(method, path, query, body, attempt)
      uri = build_uri(path, query)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      raw = http_for(uri).request(build_request(method, uri, body))
      response = to_response(raw)

      Instrumentation.request(
        method: method,
        path: path,
        status: response.status,
        duration: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
        attempt: attempt,
        rate_limit_remaining: response.rate_limit_remaining
      )
      RateLimit.record(@client, response)
      response
    end

    def build_uri(path, query)
      uri = URI.parse("#{@client.base_url}#{path}")
      uri.query = URI.encode_www_form(query) if query && !query.empty?
      uri
    end

    def build_request(method, uri, body)
      request = Net::HTTP.const_get(method.to_s.capitalize).new(uri)

      request["Accept"] = "application/json"
      request["User-Agent"] = @client.user_agent
      @client.auth.apply(request)

      if body
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
      end

      request
    end

    def http_for(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @client.open_timeout
      http.read_timeout = @client.read_timeout
      http
    end

    def to_response(raw)
      status = raw.code.to_i

      Response.new(
        status: status,
        headers: raw.each_header.to_h { |k, v| [k.to_s.downcase, v] },
        body: parse_body(raw, status)
      )
    end

    # 204 responses carry no body, and several endpoints use them; parsing one
    # as JSON would raise on an empty string.
    def parse_body(raw, status)
      return nil if status == 204

      text = raw.body
      return nil if text.nil? || text.strip.empty?

      begin
        JSON.parse(text)
      rescue JSON::ParserError
        # A 2xx that is not parseable is a genuine failure. An error response
        # with an HTML body (from an edge proxy, say) must still become a typed
        # error, so hand the raw text through for the error to carry.
        raise Error, "Malformed JSON in #{status} response" if status < 400

        text
      end
    end

    def backoff(attempt)
      delay = backoff_delay(attempt)
      sleep(delay) if delay
    end

    # Exponential backoff with jitter, capped at the rate-limit window length.
    #
    # Flodesk sends no rate-limit reset header, so no correct wait is
    # computable; this is a documented heuristic. Returns nil when backoff is
    # disabled. Kept pure and separate from the sleep so it can be asserted
    # directly without a timing-dependent test.
    def backoff_delay(attempt)
      base = @client.backoff_base
      return nil if base.nil? || base.zero?

      capped = [base * (2**(attempt - 1)), MAX_BACKOFF_SECONDS].min
      # Jitter over the lower half, so concurrent callers desynchronize instead
      # of retrying in lockstep.
      capped * (0.5 + (Kernel.rand * 0.5))
    end
  end
end
