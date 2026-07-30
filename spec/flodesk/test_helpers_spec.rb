# frozen_string_literal: true

require "flodesk/test_helpers"

RSpec.describe Flodesk::TestHelpers do
  include described_class

  let(:client) { Flodesk::Client.new(api_key: "k", backoff_base: 0) }

  describe "opt-in loading" do
    it "is not loaded by requiring flodesk alone" do
      # Verified in a clean process: requiring the gem must not pull in WebMock
      # or the helpers.
      script = 'require "flodesk"; ' \
               "print [defined?(Flodesk::TestHelpers), defined?(WebMock)].inspect"
      output = `ruby -Ilib -e '#{script}' 2>&1`

      expect(output).to eq("[nil, nil]")
    end
  end

  describe "fixture payloads" do
    it "builds a subscriber payload covering every documented field" do
      payload = flodesk_subscriber

      expect(payload.keys).to include(
        "id", "status", "email", "source", "first_name", "last_name",
        "segments", "custom_fields", "optin_ip", "optin_timestamp", "created_at"
      )
    end

    it "parses cleanly into a Subscriber" do
      subscriber = Flodesk::Subscriber.from(flodesk_subscriber)

      expect(subscriber.status).to eq(:active)
      expect(subscriber.source).to eq(:manual)
      expect(subscriber.created_at).to be_a(Time)
    end

    it "accepts overrides with symbol keys" do
      expect(flodesk_subscriber(email: "x@y.com")["email"]).to eq("x@y.com")
    end

    it "builds a segment payload that parses into a Segment" do
      expect(Flodesk::Segment.from(flodesk_segment).name).to eq("Test Segment")
    end

    it "builds a webhook payload that parses into a Webhook" do
      expect(Flodesk::Webhook.from(flodesk_webhook).events).to eq(["subscriber.created"])
    end

    it "builds a list envelope with meta shaped as the API returns it" do
      envelope = flodesk_list([flodesk_subscriber], page: 2, total_pages: 3)

      expect(envelope["meta"]).to include("page" => 2, "total_pages" => 3)
      expect(envelope["data"].size).to eq(1)
    end
  end

  describe "stubbing successful calls" do
    it "stubs a subscriber upsert" do
      stub_flodesk_upsert(email: "a@b.com")

      expect(client.subscribers.upsert(email: "a@b.com").email).to eq("a@b.com")
    end

    it "stubs a subscriber retrieval" do
      stub_flodesk_retrieve("sub_1")

      expect(client.subscribers.retrieve("sub_1").id).to eq("sub_1")
    end

    it "stubs a retrieval by email, encoding the path" do
      stub_flodesk_retrieve("a@b.com")

      expect { client.subscribers.retrieve("a@b.com") }.not_to raise_error
    end

    it "stubs a subscriber list" do
      stub_flodesk_list_subscribers([flodesk_subscriber, flodesk_subscriber(id: "sub_2")])

      page = client.subscribers.list

      expect(page.items.size).to eq(2)
      expect(page.items).to all(be_a(Flodesk::Subscriber))
    end
  end

  describe "stubbing errors" do
    it "stubs a 404 that raises NotFoundError" do
      stub_flodesk_error(:get, "/subscribers/nope", status: 404)

      expect { client.subscribers.retrieve("nope") }.to raise_error(Flodesk::NotFoundError)
    end

    it "stubs a 401 that raises AuthenticationError" do
      stub_flodesk_error(:get, "/segments/colors", status: 401)

      expect { client.segments.colors }.to raise_error(Flodesk::AuthenticationError)
    end

    it "uses the live API's error envelope shape" do
      stub_flodesk_error(:get, "/subscribers/x", status: 404,
                                                 code: "not_found", message: "No such subscriber")

      client.subscribers.retrieve("x")
    rescue Flodesk::NotFoundError => e
      expect(e.code).to eq("not_found")
      expect(e.message).to eq("No such subscriber")
    end

    it "stubs a rate-limited response with the headers the API sends" do
      stub_flodesk_rate_limited(:get, "/subscribers")

      expect { client.subscribers.list }.to raise_error(Flodesk::RateLimitError) do |error|
        expect(error.rate_limit).to eq(100)
        expect(error.rate_limit_remaining).to eq(0)
        # The API sends no reset header, so there is nothing to report.
        expect(error.retry_after).to be_nil
      end
    end
  end

  describe "stubbing batch partial failure" do
    it "stubs an all-success batch" do
      stub_flodesk_batch(successes: [flodesk_subscriber])

      expect(client.subscribers.batch_upsert([{ email: "a@b.com" }]).success?).to be(true)
    end

    it "stubs a partial failure that raises PartialFailureError by default" do
      stub_flodesk_batch(
        successes: [flodesk_subscriber],
        failures: [flodesk_batch_failure(index: 1)]
      )

      expect { client.subscribers.batch_upsert([{ email: "a@b.com" }, { email: "bad@" }]) }
        .to raise_error(Flodesk::PartialFailureError)
    end

    it "carries the parsed failures on the raised error" do
      stub_flodesk_batch(failures: [flodesk_batch_failure(index: 0, code: "invalid_email")])

      client.subscribers.batch_upsert([{ email: "bad@" }])
    rescue Flodesk::PartialFailureError => e
      expect(e.result.failures.first.code).to eq("invalid_email")
      expect(e.result.failures.first.index).to eq(0)
    end
  end

  describe "no real HTTP" do
    it "raises rather than reaching the network when a call is not stubbed" do
      expect { client.subscribers.retrieve("unstubbed") }
        .to raise_error(WebMock::NetConnectNotAllowedError)
    end
  end
end
