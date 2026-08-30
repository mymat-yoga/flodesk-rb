# frozen_string_literal: true

# PII must never reach an error message, a log line, or instrumentation.
#
# Several paths accept an email address in place of an id, so the request path
# itself carries PII — and transport errors interpolate that path into their
# message. These examples pin that down at every exit point.
RSpec.describe "PII containment" do
  let(:base) { "https://example.test/v1" }
  # Deliberately obvious as a fixture, so secret scanners have nothing to flag.
  let(:api_key) { "fd_NOT_A_REAL_KEY_test_fixture_only" }
  let(:email) { "private+tag@example.invalid" }
  let(:client) do
    Flodesk::Client.new(api_key: api_key, base_url: base, backoff_base: 0, max_retries: 0)
  end

  def encoded = "private%2Btag%40example.invalid"

  describe "transport error messages" do
    it "redacts an email path in a TimeoutError" do
      stub_request(:get, "#{base}/subscribers/#{encoded}").to_timeout

      client.subscribers.retrieve(email)
    rescue Flodesk::TimeoutError => e
      expect(e.message).not_to include("private")
      expect(e.message).not_to include("example.invalid")
      expect(e.message).to include("REDACTED")
    end

    it "redacts an email path in a ConnectionError" do
      stub_request(:get, "#{base}/subscribers/#{encoded}").to_raise(Errno::ECONNREFUSED)

      client.subscribers.retrieve(email)
    rescue Flodesk::ConnectionError => e
      expect(e.message).not_to include("private")
      expect(e.message).to include("REDACTED")
    end

    it "leaves a non-email path readable, so errors stay debuggable" do
      stub_request(:get, "#{base}/subscribers/sub_1").to_timeout

      client.subscribers.retrieve("sub_1")
    rescue Flodesk::TimeoutError => e
      expect(e.message).to include("/subscribers/sub_1")
    end
  end

  describe "validation error messages" do
    # Rejecting unknown keys means building an error message out of caller
    # input. The key names are safe to echo; the values are not — an unknown
    # field is exactly where someone puts a phone number or a date of birth.
    it "names the rejected field but never its value" do
      expect { client.subscribers.upsert(email: email, ssn: "123-45-6789") }
        .to raise_error(ArgumentError) { |e|
          expect(e.message).to include("ssn")
          expect(e.message).not_to include("123-45-6789")
        }
    end

    it "does not echo the subscriber's email when rejecting a field" do
      expect { client.subscribers.upsert(email: email, nope: 1) }
        .to raise_error(ArgumentError) { |e|
          expect(e.message).not_to include(email)
          expect(e.message).not_to include("private")
        }
    end

    it "identifies a batch record by index rather than by email" do
      records = [{ email: "a@b.com" }, { email: email, nope: 1 }]

      expect { client.subscribers.batch_upsert(records) }
        .to raise_error(ArgumentError) { |e|
          expect(e.message).to include("index 1")
          expect(e.message).not_to include(email)
        }
    end
  end

  describe "the API key" do
    it "never appears in the client's inspect output" do
      expect(client.inspect).not_to include(api_key)
    end

    it "never appears in the auth strategy's inspect output" do
      expect(client.auth.inspect).not_to include(api_key)
    end

    it "never appears in an error raised by a failing request" do
      stub_request(:get, "#{base}/segments/colors").to_return(status: 401, body: "{}")

      client.segments.colors
    rescue Flodesk::AuthenticationError => e
      expect(e.message).not_to include(api_key)
      expect(e.inspect).not_to include(api_key)
    end

    it "is not exposed through the client's string form" do
      expect(client.to_s).not_to include(api_key)
    end
  end

  describe "Redaction.payload" do
    it "removes email, custom fields and opt-in IP while preserving structure" do
      redacted = Flodesk::Redaction.payload(
        "id" => "sub_1",
        "email" => email,
        "optin_ip" => "203.0.113.9",
        "custom_fields" => { "tier" => "gold" }
      )

      expect(redacted["id"]).to eq("sub_1")
      expect(redacted["email"]).to eq("[REDACTED]")
      expect(redacted["optin_ip"]).to eq("[REDACTED]")
      expect(redacted["custom_fields"]).to eq("[REDACTED]")
    end

    it "recurses into nested structures" do
      redacted = Flodesk::Redaction.payload(
        "subscriber" => { "email" => email, "id" => "sub_1" }
      )

      expect(redacted["subscriber"]["email"]).to eq("[REDACTED]")
      expect(redacted["subscriber"]["id"]).to eq("sub_1")
    end

    it "recurses into arrays" do
      redacted = Flodesk::Redaction.payload([{ "email" => email }])

      expect(redacted.first["email"]).to eq("[REDACTED]")
    end

    it "leaves scalars untouched" do
      expect(Flodesk::Redaction.payload("plain")).to eq("plain")
      expect(Flodesk::Redaction.payload(nil)).to be_nil
    end
  end

  describe "Redaction.path" do
    it "redacts a literal email" do
      expect(Flodesk::Redaction.path("/subscribers/a@b.com")).to eq("/subscribers/[REDACTED]")
    end

    it "redacts a percent-encoded email, which is the form the transport sees" do
      expect(Flodesk::Redaction.path("/subscribers/a%40b.com")).to eq("/subscribers/[REDACTED]")
    end

    it "redacts an uppercase-encoded email" do
      expect(Flodesk::Redaction.path("/subscribers/a%40b.com/segments"))
        .to eq("/subscribers/[REDACTED]/segments")
    end

    it "preserves surrounding path segments" do
      expect(Flodesk::Redaction.path("/workflows/wf_1/subscribers/a%40b.com"))
        .to eq("/workflows/wf_1/subscribers/[REDACTED]")
    end

    it "leaves an id-only path intact" do
      expect(Flodesk::Redaction.path("/subscribers/sub_1")).to eq("/subscribers/sub_1")
    end
  end

  describe "webhook events" do
    let(:token) { "t" * 32 }
    let(:handler) { Flodesk::Webhooks::Handler.new(token: token) }
    let(:payload) do
      JSON.generate(
        "event_name" => "subscriber.created",
        "event_time" => "2024-01-01T00:00:00.000Z",
        "webhook_id" => "wh_1",
        "subscriber" => { "id" => "sub_1", "email" => email, "optin_ip" => "203.0.113.9" }
      )
    end

    it "keeps PII out of inspect" do
      event = handler.call(body: payload, token: token)

      expect(event.inspect).not_to include("private")
      expect(event.inspect).not_to include("203.0.113.9")
    end

    it "keeps PII out of the dedupe key applications persist" do
      key = handler.call(body: payload, token: token).dedupe_key

      expect(key).not_to include("private")
      expect(key).not_to include("203.0.113.9")
      expect(key).to match(/\A[0-9a-f]{64}\z/)
    end

    it "keeps the token out of a verification failure message" do
      handler.call(body: payload, token: "wrong-but-long-enough-to-be-plausible")
    rescue Flodesk::Webhooks::VerificationError => e
      expect(e.message).not_to include(token)
      expect(e.message).not_to include("wrong-but-long-enough")
    end

    it "still hands the email to the application" do
      # Containment is about logs, not about withholding data from the caller.
      expect(handler.call(body: payload, token: token).subscriber.email).to eq(email)
    end
  end
end
