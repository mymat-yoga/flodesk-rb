# frozen_string_literal: true

RSpec.describe Flodesk::Resources::Webhooks do
  let(:base) { "https://example.test/v1" }
  let(:client) { Flodesk::Client.new(api_key: "k", base_url: base, backoff_base: 0) }
  let(:webhooks) { client.webhooks }

  let(:webhook_json) do
    {
      "id" => "wh_1",
      "post_url" => "https://app.test/hooks",
      "events" => ["subscriber.created"],
      "created_at" => "2023-01-01T00:00:00.000Z"
    }.to_json
  end

  describe "#list" do
    it "issues GET /webhooks and returns a page of Webhook objects" do
      stub_request(:get, "#{base}/webhooks").to_return(
        status: 200, body: { "meta" => { "page" => 1 }, "data" => [{ "id" => "wh_1" }] }.to_json
      )

      expect(webhooks.list.items).to all(be_a(Flodesk::Webhook))
    end

    it "returns an empty page when no webhooks are registered" do
      stub_request(:get, "#{base}/webhooks").to_return(status: 200, body: { "data" => [] }.to_json)

      expect(webhooks.list).to be_empty
    end
  end

  describe "#retrieve" do
    it "issues GET /webhooks/{id}" do
      stub_request(:get, "#{base}/webhooks/wh_1").to_return(status: 200, body: webhook_json)

      expect(webhooks.retrieve("wh_1").post_url).to eq("https://app.test/hooks")
    end

    it "raises NotFoundError when the webhook does not exist" do
      stub_request(:get, "#{base}/webhooks/nope").to_return(status: 404, body: "{}")

      expect { webhooks.retrieve("nope") }.to raise_error(Flodesk::NotFoundError)
    end
  end

  describe "#create" do
    it "issues POST /webhooks with name, post_url and events, returning a 201" do
      req = stub_request(:post, "#{base}/webhooks")
            .with(
              body: {
                "name" => "My hook",
                "post_url" => "https://app.test/hooks",
                "events" => ["subscriber.created"]
              }
            ).to_return(status: 201, body: webhook_json)

      result = webhooks.create(
        name: "My hook", post_url: "https://app.test/hooks", events: ["subscriber.created"]
      )

      expect(result.id).to eq("wh_1")
      expect(req).to have_been_requested
    end

    it "accepts a single event without an array" do
      req = stub_request(:post, "#{base}/webhooks")
            .with(body: hash_including("events" => ["subscriber.created"]))
            .to_return(status: 201, body: webhook_json)

      webhooks.create(name: "n", post_url: "https://app.test/h", events: "subscriber.created")

      expect(req).to have_been_requested
    end

    it "accepts all three documented events" do
      req = stub_request(:post, "#{base}/webhooks")
            .with(
              body: hash_including(
                "events" => %w[subscriber.created subscriber.added_to_segment
                               subscriber.unsubscribed]
              )
            ).to_return(status: 201, body: webhook_json)

      webhooks.create(
        name: "n", post_url: "https://app.test/h", events: Flodesk::Enums::WEBHOOK_EVENTS
      )

      expect(req).to have_been_requested
    end

    it "rejects an event name outside the three Flodesk delivers" do
      expect do
        webhooks.create(name: "n", post_url: "https://app.test/h", events: ["subscriber.deleted"])
      end.to raise_error(ArgumentError, /events/)

      expect(a_request(:post, "#{base}/webhooks")).not_to have_been_made
    end

    it "requires a name, which the API marks required" do
      expect { webhooks.create(name: nil, post_url: "https://app.test/h", events: []) }
        .to raise_error(ArgumentError, /name/)
    end

    it "requires a post_url" do
      expect { webhooks.create(name: "n", post_url: nil, events: ["subscriber.created"]) }
        .to raise_error(ArgumentError, /post_url/)
    end

    it "requires at least one event" do
      expect { webhooks.create(name: "n", post_url: "https://app.test/h", events: []) }
        .to raise_error(ArgumentError, /events/)
    end

    it "is NOT retried on a server error, to avoid registering a duplicate webhook" do
      req = stub_request(:post, "#{base}/webhooks").to_return(status: 503, body: "{}")

      expect do
        webhooks.create(name: "n", post_url: "https://app.test/h", events: ["subscriber.created"])
      end.to raise_error(Flodesk::ServerError)

      expect(req).to have_been_requested.once
    end

    it "raises BadRequestError without retrying on a 400" do
      req = stub_request(:post, "#{base}/webhooks").to_return(status: 400, body: "{}")

      expect do
        webhooks.create(name: "n", post_url: "https://app.test/h", events: ["subscriber.created"])
      end.to raise_error(Flodesk::BadRequestError)

      expect(req).to have_been_requested.once
    end
  end

  describe "#update" do
    it "issues PUT /webhooks/{id}" do
      req = stub_request(:put, "#{base}/webhooks/wh_1")
            .with(body: hash_including("post_url" => "https://app.test/new"))
            .to_return(status: 200, body: webhook_json)

      webhooks.update("wh_1", post_url: "https://app.test/new")

      expect(req).to have_been_requested
    end

    it "returns the updated Webhook" do
      stub_request(:put, "#{base}/webhooks/wh_1").to_return(status: 200, body: webhook_json)

      expect(webhooks.update("wh_1", name: "renamed")).to be_a(Flodesk::Webhook)
    end

    it "sends only the fields supplied, since PUT fields are all optional here" do
      req = stub_request(:put, "#{base}/webhooks/wh_1")
            .with(body: { "name" => "renamed" }).to_return(status: 200, body: webhook_json)

      webhooks.update("wh_1", name: "renamed")

      expect(req).to have_been_requested
    end

    it "validates event names on update too" do
      expect { webhooks.update("wh_1", events: ["nope"]) }.to raise_error(ArgumentError, /events/)
    end

    it "raises NotFoundError when the webhook does not exist" do
      stub_request(:put, "#{base}/webhooks/nope").to_return(status: 404, body: "{}")

      expect { webhooks.update("nope", name: "x") }.to raise_error(Flodesk::NotFoundError)
    end

    it "is retried on a server error, because PUT replaces state" do
      req = stub_request(:put, "#{base}/webhooks/wh_1")
            .to_return({ status: 503, body: "{}" }, { status: 200, body: webhook_json })

      webhooks.update("wh_1", name: "x")

      expect(req).to have_been_requested.twice
    end

    it "requires at least one field to update" do
      expect { webhooks.update("wh_1") }.to raise_error(ArgumentError)
    end
  end

  describe "#delete" do
    it "issues DELETE /webhooks/{id} and returns nil without parsing the 204 body" do
      req = stub_request(:delete, "#{base}/webhooks/wh_1").to_return(status: 204, body: "")

      expect(webhooks.delete("wh_1")).to be_nil
      expect(req).to have_been_requested
    end

    it "raises NotFoundError when the webhook is already gone" do
      stub_request(:delete, "#{base}/webhooks/nope").to_return(status: 404, body: "{}")

      expect { webhooks.delete("nope") }.to raise_error(Flodesk::NotFoundError)
    end

    it "is retried on a server error, because deletes are idempotent" do
      req = stub_request(:delete, "#{base}/webhooks/wh_1")
            .to_return({ status: 503, body: "{}" }, { status: 204, body: "" })

      webhooks.delete("wh_1")

      expect(req).to have_been_requested.twice
    end
  end
end
