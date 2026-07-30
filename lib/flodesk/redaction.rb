# frozen_string_literal: true

module Flodesk
  # Strips personally identifiable information from anything the gem logs or
  # instruments.
  #
  # Two facts make this necessary rather than optional. Several paths accept an
  # email address in place of an id, so the request path itself can carry PII.
  # And webhook payloads embed both `email` and `optin_ip`.
  module Redaction
    # Fields that must never appear in log or instrumentation output.
    SENSITIVE_KEYS = %w[email custom_fields optin_ip].freeze

    PLACEHOLDER = "[REDACTED]"

    # A path segment holding an email address, standing in for an id.
    #
    # Matches both the literal "@" and its percent-encoded form. By the time a
    # path reaches here the segment has usually been encoded already, so
    # checking only for "@" would let `a%40b.com` through — which is exactly how
    # an email address ends up in a log.
    EMAIL_IN_SEGMENT = /@|%40/i

    def self.path(path)
      path.to_s
          .split("/")
          .map { |segment| segment.match?(EMAIL_IN_SEGMENT) ? PLACEHOLDER : segment }
          .join("/")
    end

    # Recursively removes sensitive values, preserving structure so the shape of
    # a payload stays debuggable.
    def self.payload(value)
      case value
      when Hash
        value.to_h do |k, v|
          SENSITIVE_KEYS.include?(k.to_s) ? [k, PLACEHOLDER] : [k, payload(v)]
        end
      when Array
        value.map { |v| payload(v) }
      else
        value
      end
    end
  end
end
