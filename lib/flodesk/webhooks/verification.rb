# frozen_string_literal: true

require "securerandom"

module Flodesk
  module Webhooks
    # Raised when an inbound request cannot be established as genuine.
    #
    # Messages deliberately carry no detail: the payload holds PII and the
    # comparison involves a secret, neither of which may reach a log.
    class VerificationError < Error
      def initialize(msg = "Webhook verification failed")
        super
      end
    end

    # Raised when a verified request's body cannot be understood.
    class InvalidPayloadError < Error; end

    # Helpers for establishing that an inbound webhook is genuine.
    #
    # Flodesk signs nothing. The API description declares `security: []` on all
    # three webhook events, so there is no signature header to check and anyone
    # who learns a callback URL can forge a delivery. The two viable defenses are
    # a secret embedded in the callback path, and re-fetching the subscriber and
    # trusting only that. IP allowlisting is not viable: Flodesk publishes no
    # ranges.
    module Verification
      # Minimum acceptable length for a path token. 32 characters of the
      # generated alphabet is comfortably beyond guessing.
      MIN_TOKEN_LENGTH = 32

      # Bytes of entropy for a generated token.
      TOKEN_BYTES = 32

      module_function

      # A URL-safe random token suitable for embedding in a callback path.
      def generate_token
        SecureRandom.urlsafe_base64(TOKEN_BYTES).delete("=")
      end

      # Compares two strings in constant time, so response timing cannot be used
      # to recover the expected value one character at a time.
      def secure_compare(expected, supplied)
        return false if expected.nil? || supplied.nil?

        expected = expected.to_s.b
        supplied = supplied.to_s.b

        # Comparing digests rather than the raw strings keeps the comparison
        # constant-time even when the lengths differ, which a plain byte-wise
        # loop cannot do without leaking length.
        expected_digest = OpenSSL::Digest::SHA256.digest(expected)
        supplied_digest = OpenSSL::Digest::SHA256.digest(supplied)

        OpenSSL.secure_compare(expected_digest, supplied_digest) && expected.bytesize == supplied.bytesize
      end
    end
  end
end
