# frozen_string_literal: true

module Flodesk
  # The outcome of a batch operation.
  #
  # `POST /subscribers/batch` is the only endpoint in this API where success and
  # failure arrive in the *same* 200 response. A client that treats 2xx as
  # success silently drops subscribers, which is why this is a first-class object
  # with an explicit {#success?} rather than a bare hash, and why
  # `batch_upsert` raises {PartialFailureError} unless told not to.
  BatchResult = Data.define(:successes, :failures, :raw) do
    def self.from(payload)
      payload ||= {}

      new(
        successes: Coercion.array_of(Subscriber, payload["successes"]),
        failures: Coercion.array_of(BatchItemError, payload["failures"]),
        raw: Coercion.snapshot(payload)
      )
    end

    # True when every submitted record was accepted.
    def success?
      failures.empty?
    end

    # Total records accounted for in the response.
    def size
      successes.size + failures.size
    end

    # Emails of the records that failed, for assembling a retry batch. Failures
    # that carry no email — matched by id — are omitted.
    def failed_emails
      failures.filter_map(&:email)
    end

    # The payload exactly as the API sent it, including any field this gem does
    # not declare.
    def to_h
      raw
    end
  end
end
