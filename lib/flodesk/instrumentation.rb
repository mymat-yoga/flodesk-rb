# frozen_string_literal: true

module Flodesk
  # Emits `flodesk.request` notifications when ActiveSupport is available.
  #
  # One event is emitted per *attempt*, not per logical call, so retries are
  # visible in whatever collects them. Payloads carry no PII: no request body, no
  # response body, no API key, and any email embedded in a path is redacted.
  module Instrumentation
    EVENT_NAME = "flodesk.request"

    module_function

    # True when ActiveSupport::Notifications can be published to. Checked per
    # call rather than cached, since a host application may load ActiveSupport
    # after this gem.
    def available?
      defined?(ActiveSupport::Notifications) ? true : false
    end

    def request(method:, path:, status:, duration:, attempt:, rate_limit_remaining:)
      return unless available?

      ActiveSupport::Notifications.instrument(
        EVENT_NAME,
        method: method.to_s.upcase,
        endpoint: Redaction.path(path),
        status: status,
        duration: duration,
        attempt: attempt,
        rate_limit_remaining: rate_limit_remaining
      )
    end
  end
end
