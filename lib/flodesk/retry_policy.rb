# frozen_string_literal: true

module Flodesk
  # Decides whether a failed request may be retried.
  #
  # This is a distinct concept in this client because Flodesk offers no
  # idempotency-key header, so the only thing making a retry safe is knowing
  # that the operation is naturally idempotent. That knowledge lives with each
  # endpoint, and this class is where it is applied.
  class RetryPolicy
    # Whether repeating the operation is safe.
    attr_reader :idempotent

    # Whether a 429 may be retried. False only for POST /campaigns/canva, where
    # a 429 cannot prove the campaign was not accepted.
    attr_reader :retry_rate_limit

    # Maximum retries after the initial attempt.
    attr_reader :max_retries

    def initialize(idempotent:, retry_rate_limit:, max_retries:)
      @idempotent = idempotent
      @retry_rate_limit = retry_rate_limit
      @max_retries = max_retries
      freeze
    end

    # True when `error` may be retried on attempt number `attempt`.
    def retry?(error, attempt)
      attempt <= max_retries && retriable_error?(error)
    end

    private

    def retriable_error?(error)
      case error
      when RateLimitError then retry_rate_limit
      when ServerError, TimeoutError, ConnectionError then idempotent
      else
        # Every other 4xx is caused by the request itself and cannot succeed on
        # a second identical attempt.
        false
      end
    end
  end
end
