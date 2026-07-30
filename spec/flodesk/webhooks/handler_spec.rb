# frozen_string_literal: true

RSpec.describe Flodesk::Webhooks::Handler do
  let(:base) { "https://example.test/v1" }
  let(:client) { Flodesk::Client.new(api_key: "k", base_url: base, backoff_base: 0) }
  let(:token) { "t" * 32 }

  let(:created_payload) do
    {
      "event_name" => "subscriber.created",
      "event_time" => "2023-01-02T15:04:05.999Z",
      "webhook_id" => "wh_1",
      "subscriber" => {
        "id" => "sub_1", "email" => "a@b.com", "status" => "active",
        "optin_ip" => "203.0.113.5"
      }
    }
  end

  def body(payload = created_payload)
    JSON.generate(payload)
  end

  describe "mandatory verification" do
    it "raises when constructed with no verification strategy" do
      expect { described_class.new }.to raise_error(ArgumentError, /verification/i)
    end

    it "builds successfully with the token strategy" do
      expect(described_class.new(token: token)).to be_a(described_class)
    end

    it "builds successfully with the refetch strategy" do
      expect(described_class.new(verify: :refetch, client: client)).to be_a(described_class)
    end

    it "raises when the refetch strategy is chosen without a client" do
      expect { described_class.new(verify: :refetch) }.to raise_error(ArgumentError, /client/)
    end

    it "raises on an unknown strategy" do
      expect { described_class.new(verify: :trust_me) }.to raise_error(ArgumentError)
    end

    it "rejects a token that is too short to be a meaningful secret" do
      expect { described_class.new(token: "abc") }.to raise_error(ArgumentError, /token/)
    end
  end

  describe "token-in-path verification" do
    subject(:handler) { described_class.new(token: token) }

    it "accepts and parses a request carrying the registered token" do
      event = handler.call(body: body, token: token)

      expect(event).to be_a(Flodesk::Webhooks::Event)
      expect(event.event_name).to eq("subscriber.created")
    end

    it "rejects a request carrying an incorrect token" do
      expect { handler.call(body: body, token: "x" * 32) }
        .to raise_error(Flodesk::Webhooks::VerificationError)
    end

    it "rejects a request carrying no token" do
      expect { handler.call(body: body, token: nil) }
        .to raise_error(Flodesk::Webhooks::VerificationError)
    end

    it "rejects an empty token" do
      expect { handler.call(body: body, token: "") }
        .to raise_error(Flodesk::Webhooks::VerificationError)
    end

    it "does not parse the body when verification fails" do
      expect { handler.call(body: "not json at all", token: "wrong") }
        .to raise_error(Flodesk::Webhooks::VerificationError)
    end

    it "rejects a token of the correct length but wrong content" do
      expect { handler.call(body: body, token: token.succ) }
        .to raise_error(Flodesk::Webhooks::VerificationError)
    end

    it "uses a constant-time comparison so timing cannot reveal the secret" do
      expect(Flodesk::Webhooks::Verification)
        .to receive(:secure_compare).with(token, token).and_call_original

      handler.call(body: body, token: token)
    end
  end

  describe ".generate_token" do
    it "returns a cryptographically random token" do
      expect(described_class.generate_token).not_to eq(described_class.generate_token)
    end

    it "returns a token long enough to resist guessing" do
      expect(described_class.generate_token.length).to be >= 32
    end

    it "returns a URL-safe token, since it goes in a path segment" do
      expect(described_class.generate_token).to match(/\A[A-Za-z0-9_-]+\z/)
    end
  end

  describe "refetch verification" do
    subject(:handler) { described_class.new(verify: :refetch, client: client) }

    it "dispatches the re-fetched subscriber rather than the payload's copy" do
      stub_request(:get, "#{base}/subscribers/sub_1").to_return(
        status: 200,
        body: { "id" => "sub_1", "email" => "real@b.com", "status" => "active" }.to_json
      )

      # The payload claims a@b.com; the authoritative record says real@b.com.
      event = handler.call(body: body)

      expect(event.subscriber.email).to eq("real@b.com")
    end

    it "takes only the identifier from the payload" do
      req = stub_request(:get, "#{base}/subscribers/sub_1").to_return(
        status: 200, body: { "id" => "sub_1", "status" => "active" }.to_json
      )

      handler.call(body: body)

      expect(req).to have_been_requested
    end

    it "treats the event as unverified when the subscriber cannot be re-fetched" do
      stub_request(:get, "#{base}/subscribers/sub_1").to_return(status: 404, body: "{}")

      expect { handler.call(body: body) }
        .to raise_error(Flodesk::Webhooks::VerificationError)
    end

    it "raises VerificationError when the payload carries no subscriber id" do
      payload = created_payload.merge("subscriber" => { "email" => "a@b.com" })

      expect { handler.call(body: JSON.generate(payload)) }
        .to raise_error(Flodesk::Webhooks::VerificationError)
    end

    it "does not require a token" do
      stub_request(:get, "#{base}/subscribers/sub_1").to_return(
        status: 200, body: { "id" => "sub_1" }.to_json
      )

      expect { handler.call(body: body) }.not_to raise_error
    end
  end

  describe "event parsing" do
    subject(:handler) { described_class.new(token: token) }

    it "parses subscriber.created" do
      event = handler.call(body: body, token: token)

      expect(event.event_name).to eq("subscriber.created")
      expect(event.webhook_id).to eq("wh_1")
      expect(event.event_time).to be_a(Time)
      expect(event.subscriber).to be_a(Flodesk::Subscriber)
      expect(event.subscriber.id).to eq("sub_1")
    end

    it "parses subscriber.added_to_segment with its segment" do
      payload = created_payload.merge(
        "event_name" => "subscriber.added_to_segment",
        "segment" => { "id" => "seg_1", "name" => "Friends" }
      )

      event = handler.call(body: JSON.generate(payload), token: token)

      expect(event.segment).to be_a(Flodesk::Segment)
      expect(event.segment.name).to eq("Friends")
    end

    it "parses subscriber.unsubscribed" do
      payload = created_payload.merge("event_name" => "subscriber.unsubscribed")

      event = handler.call(body: JSON.generate(payload), token: token)

      expect(event.event_name).to eq("subscriber.unsubscribed")
      expect(event.subscriber.id).to eq("sub_1")
    end

    it "leaves segment nil for events that carry none" do
      expect(handler.call(body: body, token: token).segment).to be_nil
    end

    it "does not raise on an event name the gem does not know" do
      payload = created_payload.merge("event_name" => "subscriber.resurrected")

      event = nil
      expect { event = handler.call(body: JSON.generate(payload), token: token) }
        .not_to raise_error

      expect(event.event_name).to eq("subscriber.resurrected")
      expect(event.to_h["event_name"]).to eq("subscriber.resurrected")
    end

    it "reports whether the event is one Flodesk documents" do
      expect(handler.call(body: body, token: token)).to be_known

      unknown = handler.call(
        body: JSON.generate(created_payload.merge("event_name" => "nope")), token: token
      )
      expect(unknown).not_to be_known
    end

    it "rejects a malformed JSON body after verification passes" do
      expect { handler.call(body: "{not json", token: token) }
        .to raise_error(Flodesk::Webhooks::InvalidPayloadError)
    end

    it "rejects a JSON body that is not an object" do
      expect { handler.call(body: "[1,2,3]", token: token) }
        .to raise_error(Flodesk::Webhooks::InvalidPayloadError)
    end

    it "rejects an empty body" do
      expect { handler.call(body: "", token: token) }
        .to raise_error(Flodesk::Webhooks::InvalidPayloadError)
    end

    it "keeps the whole raw payload available" do
      expect(handler.call(body: body, token: token).to_h).to eq(created_payload)
    end
  end

  describe "dedupe key" do
    subject(:handler) { described_class.new(token: token) }

    it "is stable across identical deliveries" do
      first = handler.call(body: body, token: token).dedupe_key
      second = handler.call(body: body, token: token).dedupe_key

      expect(first).to eq(second)
    end

    it "differs when the event name differs" do
      other = JSON.generate(created_payload.merge("event_name" => "subscriber.unsubscribed"))

      expect(handler.call(body: body, token: token).dedupe_key)
        .not_to eq(handler.call(body: other, token: token).dedupe_key)
    end

    it "differs when the subscriber differs" do
      other = JSON.generate(
        created_payload.merge("subscriber" => { "id" => "sub_2", "status" => "active" })
      )

      expect(handler.call(body: body, token: token).dedupe_key)
        .not_to eq(handler.call(body: other, token: token).dedupe_key)
    end

    it "differs when the event time differs" do
      other = JSON.generate(created_payload.merge("event_time" => "2024-06-06T00:00:00.000Z"))

      expect(handler.call(body: body, token: token).dedupe_key)
        .not_to eq(handler.call(body: other, token: token).dedupe_key)
    end

    it "differs when the webhook id differs" do
      other = JSON.generate(created_payload.merge("webhook_id" => "wh_2"))

      expect(handler.call(body: body, token: token).dedupe_key)
        .not_to eq(handler.call(body: other, token: token).dedupe_key)
    end

    it "contains no raw PII, since applications persist this value" do
      key = handler.call(body: body, token: token).dedupe_key

      expect(key).not_to include("a@b.com")
      expect(key).not_to include("203.0.113.5")
    end
  end

  describe "PII handling" do
    subject(:handler) { described_class.new(token: token) }

    it "keeps email and opt-in IP out of a verification failure message" do
      error = nil
      begin
        handler.call(body: body, token: "wrong")
      rescue Flodesk::Webhooks::VerificationError => e
        error = e
      end

      expect(error.message).not_to include("a@b.com")
      expect(error.message).not_to include("203.0.113.5")
      expect(error.message).not_to include(token)
    end

    it "keeps the expected and supplied tokens out of the failure message" do
      error = nil
      begin
        handler.call(body: body, token: "supplied-secret")
      rescue Flodesk::Webhooks::VerificationError => e
        error = e
      end

      expect(error.message).not_to include("supplied-secret")
    end

    it "keeps PII out of the event's inspect output" do
      event = handler.call(body: body, token: token)

      expect(event.inspect).not_to include("a@b.com")
      expect(event.inspect).not_to include("203.0.113.5")
    end

    it "still exposes the subscriber's email to the application" do
      # Redaction is about logs, not about withholding data from the caller.
      expect(handler.call(body: body, token: token).subscriber.email).to eq("a@b.com")
    end
  end
end
