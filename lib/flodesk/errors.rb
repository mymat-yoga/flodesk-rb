# frozen_string_literal: true

module Flodesk
  # Base class for everything this gem raises. Rescue this to catch any Flodesk
  # failure, including transport-level ones.
  class Error < StandardError
    # Maps an HTTP response to the appropriate error instance.
    #
    # The Flodesk OpenAPI description declares *no* schema for any error
    # response — every 4xx documents only an empty description. The
    # `{"code": ..., "message": ...}` envelope parsed here was established by
    # probing the live API, so it is not contract-verifiable and must never be
    # assumed present. An unexpected body degrades to a status-derived message
    # rather than raising while building the error.
    def self.from_response(status:, body: nil, headers: {})
      klass_for(status).new(status: status, body: body, headers: headers)
    end

    def self.klass_for(status)
      case status
      when 400 then BadRequestError
      when 401, 403 then AuthenticationError
      when 404 then NotFoundError
      when 429 then RateLimitError
      when 500..599 then ServerError
      else APIError
      end
    end
    private_class_method :klass_for
  end

  # Raised when Flodesk returns an HTTP error response, as opposed to the
  # request failing before a response was received.
  class APIError < Error
    # The HTTP status code of the response.
    attr_reader :status

    # The `code` field from the error envelope, or nil when absent.
    attr_reader :code

    # The response body exactly as parsed, for debugging unexpected shapes.
    attr_reader :raw_body

    def initialize(status:, body: nil, headers: {})
      @status = status
      @raw_body = body
      @headers = normalize_headers(headers)
      @code = extract(body, "code")

      super(extract(body, "message") || "HTTP #{status}")
    end

    # Value of `X-Fd-RateLimit-Limit`, or nil when the header was absent.
    def rate_limit
      integer_header("x-fd-ratelimit-limit")
    end

    # Value of `X-Fd-RateLimit-Remaining`, or nil when the header was absent.
    def rate_limit_remaining
      integer_header("x-fd-ratelimit-remaining")
    end

    private

    # Reads a field from the envelope, tolerating any body shape. A body may be
    # a parsed Hash, an HTML string from an edge proxy, or nil.
    def extract(body, key)
      return nil unless body.is_a?(Hash)

      value = body[key] || body[key.to_sym]
      value.is_a?(String) && !value.empty? ? value : nil
    end

    def normalize_headers(headers)
      return {} unless headers.respond_to?(:each_pair)

      headers.each_pair.to_h { |k, v| [k.to_s.downcase, v] }
    end

    def integer_header(name)
      value = @headers[name]
      value = value.first if value.is_a?(Array)
      return nil if value.nil? || value.to_s.empty?

      Integer(value, exception: false)
    end
  end

  # 400 — the request payload was rejected. Never retried: the same payload
  # cannot succeed on a second attempt.
  class BadRequestError < APIError; end

  # 401 or 403 — the API key was missing, malformed, or not accepted.
  class AuthenticationError < APIError; end

  # 404 — the addressed resource does not exist.
  class NotFoundError < APIError; end

  # 5xx — Flodesk failed to process an otherwise valid request.
  class ServerError < APIError; end

  # 429 — the rate limit was exceeded.
  #
  # Flodesk returns `X-Fd-RateLimit-Limit` and `X-Fd-RateLimit-Remaining` but
  # *no reset header*, so there is no way to compute when the window reopens.
  # `retry_after` therefore always returns nil, and any backoff this gem applies
  # is a documented heuristic rather than a computed wait.
  class RateLimitError < APIError
    # Always nil: the API exposes no reset time. Present so callers can ask
    # without special-casing, and to document the absence explicitly.
    def retry_after
      nil
    end
  end

  # The request failed before a response was received.
  class ConnectionError < Error; end

  # The request exceeded a configured connect or read timeout.
  #
  # For non-idempotent operations a timeout is genuinely ambiguous: the write
  # may have been applied. Such operations are never retried.
  class TimeoutError < Error; end

  # Raised when a batch operation returns 200 while reporting per-record
  # failures. Carries the complete result, so records that succeeded remain
  # available to the caller and no work is lost by raising.
  class PartialFailureError < Error
    # The BatchResult describing both successes and failures.
    attr_reader :result

    def initialize(result:)
      @result = result

      super("#{result.failures.size} of " \
            "#{result.failures.size + result.successes.size} records failed")
    end
  end
end
