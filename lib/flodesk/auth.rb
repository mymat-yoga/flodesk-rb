# frozen_string_literal: true

module Flodesk
  # Authentication strategies.
  #
  # Only API-key (HTTP Basic) auth is implemented. This seam exists so OAuth2
  # bearer tokens can be added later without changing Connection: partner
  # integrations need an authorization-code flow with token storage, expiry, and
  # single-use refresh-token rotation, which is a subsystem rather than a
  # feature and is deliberately out of scope for v1.
  module Auth
    # Flodesk expects the API key as the HTTP Basic username with an empty
    # password.
    class ApiKey
      def initialize(api_key)
        @api_key = api_key
        freeze
      end

      def apply(request)
        request.basic_auth(@api_key, "")
        request
      end

      # Never interpolate the key into logs or inspect output.
      def inspect
        "#<#{self.class.name} api_key=[REDACTED]>"
      end
      alias to_s inspect
    end
  end
end
