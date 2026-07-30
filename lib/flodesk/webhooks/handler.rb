# frozen_string_literal: true

require "json"
require "openssl"

module Flodesk
  # Handling of inbound webhook deliveries from Flodesk.
  module Webhooks
    # The verification strategies a handler can be built with.
    STRATEGIES = %i[token refetch].freeze

    # Verifies and parses inbound webhook deliveries.
    #
    # A verification strategy is **mandatory**. Flodesk signs nothing, so a
    # handler that accepted any POST would let anyone who learns the callback URL
    # forge subscriber events. Constructing without choosing a strategy raises
    # rather than defaulting to trust.
    #
    # Token in the callback path — cheap, no extra API call:
    #
    #   token   = Flodesk::Webhooks::Handler.generate_token
    #   handler = Flodesk::Webhooks::Handler.new(token: token)
    #   # register post_url "https://app.example.com/flodesk/#{token}"
    #   event = handler.call(body: request.raw_post, token: params[:token])
    #
    # Note that the token then appears in server access logs and Rails request
    # logs, so filter that route.
    #
    # Re-fetch — forgery-proof, costs one API call per event against the
    # 100-per-minute budget:
    #
    #   handler = Flodesk::Webhooks::Handler.new(verify: :refetch, client: FLODESK)
    #   event   = handler.call(body: request.raw_post)
    class Handler
      # A URL-safe random token suitable for embedding in a callback path.
      def self.generate_token
        Verification.generate_token
      end

      def initialize(token: nil, verify: nil, client: nil)
        @strategy = resolve_strategy(token: token, verify: verify)
        validate_strategy!(token: token, client: client)

        @token = token
        @client = client
        freeze
      end

      # Verifies `body` and returns a parsed {Event}.
      #
      # Raises {VerificationError} if authenticity cannot be established, before
      # the body is parsed. Raises {InvalidPayloadError} if a verified body
      # cannot be understood.
      def call(body:, token: nil)
        verify_token!(token) if @strategy == :token

        payload = parse!(body)

        if @strategy == :refetch
          Event.from(payload, subscriber: refetch!(payload))
        else
          Event.from(payload)
        end
      end

      # Verifies, parses, dispatches, and maps the outcome to a Rack triple.
      #
      # Flodesk treats any 2XX as "delivered" and anything else as "retry
      # later", so the status is the only backpressure signal available. An
      # exception from the application's block therefore becomes a 500: the
      # event was not processed, and Flodesk should try again rather than
      # consider it delivered.
      #
      #   post "/flodesk/:token" do
      #     status, headers, body = HANDLER.respond(
      #       body: request.raw_post, token: params[:token]
      #     ) { |event| SubscriberSync.perform_later(event.subscriber.id) }
      #   end
      #
      # `on_error` receives any exception raised by the block, so the
      # application can report its own failures rather than have them swallowed.
      def respond(body:, token: nil, on_error: nil)
        event = call(body: body, token: token)
        yield event if block_given?
        rack(200, "ok")
      rescue VerificationError
        rack(401, "unauthorized")
      rescue InvalidPayloadError
        rack(400, "bad request")
      rescue StandardError => e
        on_error&.call(e)
        rack(500, "error")
      end

      private

      # Response bodies are deliberately bare: the request payload holds PII and
      # the token is a secret, so neither may be echoed back.
      def rack(status, text)
        [status, { "content-type" => "text/plain" }, [text]]
      end

      def resolve_strategy(token:, verify:)
        return verify.to_sym if verify

        return :token if token

        raise ArgumentError,
              "a verification strategy is required: pass token: for token-in-path " \
              "verification, or verify: :refetch with a client. Flodesk does not sign " \
              "webhooks, so unverified payloads cannot be trusted."
      end

      def validate_strategy!(token:, client:)
        raise ArgumentError, "unknown verification strategy #{@strategy.inspect}" unless STRATEGIES.include?(@strategy)

        validate_token!(token) if @strategy == :token

        return unless @strategy == :refetch && client.nil?

        raise ArgumentError, "verify: :refetch requires a client to re-fetch the subscriber"
      end

      def validate_token!(token)
        return unless token.nil? || token.to_s.length < Verification::MIN_TOKEN_LENGTH

        raise ArgumentError,
              "token must be at least #{Verification::MIN_TOKEN_LENGTH} characters; " \
              "use #{self.class.name}.generate_token"
      end

      # Raises before parsing, so a forged request's body is never interpreted.
      def verify_token!(supplied)
        raise VerificationError unless Verification.secure_compare(@token, supplied)
      end

      def parse!(body)
        raise InvalidPayloadError, "webhook body was empty" if body.nil? || body.to_s.strip.empty?

        payload = begin
          JSON.parse(body)
        rescue JSON::ParserError
          # The message deliberately omits the body, which holds PII.
          raise InvalidPayloadError, "webhook body was not valid JSON"
        end

        raise InvalidPayloadError, "webhook body was not a JSON object" unless payload.is_a?(Hash)

        payload
      end

      # Treats the payload as an untrusted hint: takes only the subscriber id and
      # reads the authoritative record back from the API.
      def refetch!(payload)
        id = payload.dig("subscriber", "id")
        raise VerificationError if id.nil? || id.to_s.empty?

        begin
          @client.subscribers.retrieve(id)
        rescue Flodesk::NotFoundError
          # A subscriber that does not exist means the payload was not genuine.
          raise VerificationError
        end
      end
    end
  end
end
