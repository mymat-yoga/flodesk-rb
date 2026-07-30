# frozen_string_literal: true

module Flodesk
  # A completed HTTP response: status, normalized headers, and parsed body.
  #
  # Instances are immutable. `body` is nil for 204 responses, which several
  # endpoints return and which must never be parsed as JSON.
  Response = Data.define(:status, :headers, :body) do
    # Value of `X-Fd-RateLimit-Limit`, or nil when absent.
    def rate_limit
      integer_header("x-fd-ratelimit-limit")
    end

    # Value of `X-Fd-RateLimit-Remaining`, or nil when absent.
    def rate_limit_remaining
      integer_header("x-fd-ratelimit-remaining")
    end

    # Flodesk sends no rate-limit reset header, so no reset time exists to
    # report. Present to make the absence explicit rather than surprising.
    def rate_limit_reset
      nil
    end

    private

    def integer_header(name)
      value = headers[name]
      value = value.first if value.is_a?(Array)
      return nil if value.nil? || value.to_s.empty?

      Integer(value, exception: false)
    end
  end
end
