# frozen_string_literal: true

module Flodesk
  # Records the rate-limit state observed on the most recent response.
  #
  # Storage is thread-local by design. A client is frozen and shared across
  # threads, so it cannot hold this as mutable state; and a caller pacing itself
  # wants the limit state for *its own* requests, not whatever another thread
  # last saw.
  #
  # Flodesk sends no reset header, so `remaining` is the only actionable signal
  # available and the gem cannot guarantee staying within quota.
  module RateLimit
    State = Data.define(:limit, :remaining)

    def self.record(client, response)
      limit = response.rate_limit
      remaining = response.rate_limit_remaining
      return if limit.nil? && remaining.nil?

      Thread.current[key(client)] = State.new(limit: limit, remaining: remaining)
    end

    # The rate-limit state from this thread's most recent request through
    # `client`, or nil if none has been observed.
    def self.last(client)
      Thread.current[key(client)]
    end

    def self.key(client)
      :"flodesk_rate_limit_#{client.object_id}"
    end
    private_class_method :key
  end
end
