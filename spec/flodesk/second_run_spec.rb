# frozen_string_literal: true

# "Walk the path twice": the happy path passing once is not the same as the code
# being correct. Each example here runs a flow a second time with one variable
# changed — repeat, interleave, empty, rapid succession — because that is where
# state leaks and reset bugs live.
RSpec.describe "Repeated and edge-case flows" do
  let(:base) { "https://example.test/v1" }
  let(:client) { Flodesk::Client.new(api_key: "k", base_url: base, backoff_base: 0) }

  def subscriber_json(id: "sub_1")
    { "id" => id, "email" => "a@b.com", "status" => "active" }.to_json
  end

  def list_json(items, page: 1, total_pages: 1)
    {
      "meta" => { "page" => page, "total_pages" => total_pages,
                  "per_page" => 20, "total_items" => items.size },
      "data" => items
    }.to_json
  end

  describe "repeat: the same call twice" do
    it "upserts twice without carrying state between calls" do
      stub_request(:post, "#{base}/subscribers").to_return(status: 200, body: subscriber_json)

      first = client.subscribers.upsert(email: "a@b.com")
      second = client.subscribers.upsert(email: "a@b.com")

      expect(first).to eq(second)
    end

    it "does not accumulate query parameters across calls" do
      stub_request(:get, "#{base}/subscribers")
        .with(query: { "status" => "active" }).to_return(status: 200, body: list_json([]))
      stub_request(:get, "#{base}/subscribers")
        .with(query: {}).to_return(status: 200, body: list_json([]))

      client.subscribers.list(status: :active)
      client.subscribers.list

      # The second call must send no status filter left over from the first.
      expect(a_request(:get, "#{base}/subscribers").with(query: {})).to have_been_made
    end

    it "does not mutate the caller's arguments" do
      stub_request(:post, "#{base}/subscribers").to_return(status: 200, body: subscriber_json)
      segment_ids = %w[seg_1]
      custom_fields = { "vip" => true }

      client.subscribers.upsert(
        email: "a@b.com", segment_ids: segment_ids, custom_fields: custom_fields
      )

      expect(segment_ids).to eq(%w[seg_1])
      expect(custom_fields).to eq({ "vip" => true })
    end

    it "does not mutate the records array passed to batch_upsert" do
      stub_request(:post, "#{base}/subscribers/batch")
        .to_return(status: 200, body: { "successes" => [], "failures" => [] }.to_json)
      records = [{ email: "a@b.com", custom_fields: { "n" => 1 } }]
      snapshot = Marshal.load(Marshal.dump(records))

      client.subscribers.batch_upsert(records)

      expect(records).to eq(snapshot)
    end

    it "reuses one client for many different operations in sequence" do
      stub_request(:get, "#{base}/subscribers").to_return(status: 200, body: list_json([]))
      stub_request(:get, "#{base}/segments").to_return(status: 200, body: list_json([]))
      stub_request(:get, "#{base}/webhooks").to_return(status: 200, body: list_json([]))

      expect do
        client.subscribers.list
        client.segments.list
        client.webhooks.list
        client.subscribers.list
      end.not_to raise_error
    end
  end

  describe "repeat: retry then success then retry again" do
    it "resets the attempt counter between logical calls" do
      stub_request(:get, "#{base}/subscribers").to_return(
        { status: 503, body: "{}" }, { status: 200, body: list_json([]) },
        { status: 503, body: "{}" }, { status: 200, body: list_json([]) }
      )

      client.subscribers.list
      client.subscribers.list

      # Four requests total: two attempts for each of two calls. A leaked
      # counter would have exhausted the budget on the second call.
      expect(a_request(:get, "#{base}/subscribers")).to have_been_made.times(4)
    end

    it "still succeeds after a call that exhausted its retries" do
      stub_request(:get, "#{base}/segments").to_return(status: 503, body: "{}")
      stub_request(:get, "#{base}/subscribers").to_return(status: 200, body: list_json([]))

      expect { client.segments.list }.to raise_error(Flodesk::ServerError)
      expect { client.subscribers.list }.not_to raise_error
    end
  end

  describe "repeat: batch all-success then partial-failure on one client" do
    it "handles a clean batch followed by a failing one" do
      stub_request(:post, "#{base}/subscribers/batch").to_return(
        { status: 200, body: { "successes" => [{ "id" => "s1" }], "failures" => [] }.to_json },
        { status: 200,
          body: { "successes" => [], "failures" => [{ "index" => 0, "code" => "bad" }] }.to_json }
      )

      expect(client.subscribers.batch_upsert([{ email: "a@b.com" }]).success?).to be(true)
      expect { client.subscribers.batch_upsert([{ email: "b@c.com" }]) }
        .to raise_error(Flodesk::PartialFailureError)
    end

    it "handles a failing batch followed by a clean one" do
      stub_request(:post, "#{base}/subscribers/batch").to_return(
        { status: 200,
          body: { "successes" => [], "failures" => [{ "index" => 0, "code" => "bad" }] }.to_json },
        { status: 200, body: { "successes" => [{ "id" => "s1" }], "failures" => [] }.to_json }
      )

      expect { client.subscribers.batch_upsert([{ email: "a@b.com" }]) }
        .to raise_error(Flodesk::PartialFailureError)
      expect(client.subscribers.batch_upsert([{ email: "b@c.com" }]).success?).to be(true)
    end
  end

  describe "repeat: webhook handler processing the same event twice" do
    let(:token) { "t" * 32 }
    let(:handler) { Flodesk::Webhooks::Handler.new(token: token) }
    let(:payload) do
      JSON.generate(
        "event_name" => "subscriber.created",
        "event_time" => "2024-01-01T00:00:00.000Z",
        "webhook_id" => "wh_1",
        "subscriber" => { "id" => "sub_1", "email" => "a@b.com" }
      )
    end

    it "parses the same delivery twice to equal events" do
      first = handler.call(body: payload, token: token)
      second = handler.call(body: payload, token: token)

      expect(first).to eq(second)
      expect(first.dedupe_key).to eq(second.dedupe_key)
    end

    it "keeps working after a rejected delivery" do
      expect { handler.call(body: payload, token: "wrong") }
        .to raise_error(Flodesk::Webhooks::VerificationError)

      expect(handler.call(body: payload, token: token)).to be_a(Flodesk::Webhooks::Event)
    end

    it "keeps working after a malformed delivery" do
      expect { handler.call(body: "{bad", token: token) }
        .to raise_error(Flodesk::Webhooks::InvalidPayloadError)

      expect(handler.call(body: payload, token: token)).to be_a(Flodesk::Webhooks::Event)
    end

    it "handles a reused handler across many deliveries" do
      10.times do
        expect(handler.call(body: payload, token: token).subscriber.id).to eq("sub_1")
      end
    end
  end

  describe "empty and nil arguments across every operation" do
    it "handles an empty list response on every list endpoint" do
      %w[subscribers segments custom-fields webhooks workflows campaigns].each do |path|
        stub_request(:get, "#{base}/#{path}").to_return(status: 200, body: list_json([]))
      end

      expect(client.subscribers.list).to be_empty
      expect(client.segments.list).to be_empty
      expect(client.custom_fields.list).to be_empty
      expect(client.webhooks.list).to be_empty
      expect(client.workflows.list).to be_empty
      expect(client.campaigns.list).to be_empty
    end

    it "handles a response with a null data array" do
      stub_request(:get, "#{base}/subscribers")
        .to_return(status: 200, body: { "meta" => {}, "data" => nil }.to_json)

      expect(client.subscribers.list.items).to eq([])
    end

    it "handles a completely empty JSON object as a list response" do
      stub_request(:get, "#{base}/subscribers").to_return(status: 200, body: "{}")

      page = client.subscribers.list

      expect(page.items).to eq([])
      expect(page.more_pages?).to be(false)
    end

    it "rejects nil identifiers rather than building a malformed path" do
      expect { client.subscribers.retrieve(nil) }.to raise_error(ArgumentError)
      expect { client.segments.retrieve(nil) }.to raise_error(ArgumentError)
      expect { client.webhooks.retrieve(nil) }.to raise_error(ArgumentError)
      expect { client.subscribers.unsubscribe(nil) }.to raise_error(ArgumentError)
      expect { client.workflows.remove_subscriber(nil, "s") }.to raise_error(ArgumentError)
    end

    it "rejects empty-string identifiers" do
      expect { client.subscribers.retrieve("") }.to raise_error(ArgumentError)
      expect { client.webhooks.delete("") }.to raise_error(ArgumentError)
    end

    it "rejects empty collections where the API requires at least one element" do
      expect { client.subscribers.batch_upsert([]) }.to raise_error(ArgumentError)
      expect { client.subscribers.add_to_segments("s", []) }.to raise_error(ArgumentError)
      expect { client.subscribers.remove_from_segments("s", []) }.to raise_error(ArgumentError)
      expect { client.webhooks.create(name: "n", post_url: "u", events: []) }
        .to raise_error(ArgumentError)
    end

    it "handles nil custom_fields without sending the key" do
      req = stub_request(:post, "#{base}/subscribers")
            .with(body: { "email" => "a@b.com" }).to_return(status: 200, body: subscriber_json)

      client.subscribers.upsert(email: "a@b.com", custom_fields: nil)

      expect(req).to have_been_requested
    end

    it "handles an empty custom_fields hash" do
      req = stub_request(:post, "#{base}/subscribers")
            .with(body: { "email" => "a@b.com", "custom_fields" => {} })
            .to_return(status: 200, body: subscriber_json)

      client.subscribers.upsert(email: "a@b.com", custom_fields: {})

      expect(req).to have_been_requested
    end
  end

  describe "auto-paging traversed twice" do
    before do
      stub_request(:get, "#{base}/subscribers").with(query: {}).to_return(
        status: 200, body: list_json([{ "id" => "a" }], page: 1, total_pages: 2)
      )
      stub_request(:get, "#{base}/subscribers").with(query: { "page" => "2" }).to_return(
        status: 200, body: list_json([{ "id" => "b" }], page: 2, total_pages: 2)
      )
    end

    it "yields the same items on a second full traversal" do
      enumerator = client.subscribers.auto_paging_each

      expect(enumerator.map(&:id)).to eq(%w[a b])
      expect(enumerator.map(&:id)).to eq(%w[a b])
    end

    it "re-fetches rather than replaying a stale first page" do
      client.subscribers.auto_paging_each.to_a
      client.subscribers.auto_paging_each.to_a

      expect(a_request(:get, "#{base}/subscribers").with(query: {}))
        .to have_been_made.twice
    end

    it "can be interleaved with a plain list call" do
      expect(client.subscribers.auto_paging_each.map(&:id)).to eq(%w[a b])
      expect(client.subscribers.list.items.map(&:id)).to eq(%w[a])
      expect(client.subscribers.auto_paging_each.map(&:id)).to eq(%w[a b])
    end

    it "stops cleanly when partially consumed, twice" do
      enumerator = client.subscribers.auto_paging_each

      expect(enumerator.first(1).map(&:id)).to eq(%w[a])
      expect(enumerator.first(1).map(&:id)).to eq(%w[a])
    end
  end

  describe "rapid succession on a shared client" do
    it "handles many concurrent calls without cross-talk" do
      stub_request(:get, "#{base}/subscribers/sub_1")
        .to_return(status: 200, body: subscriber_json(id: "sub_1"))
      stub_request(:get, "#{base}/subscribers/sub_2")
        .to_return(status: 200, body: subscriber_json(id: "sub_2"))

      results = 20.times.map do |i|
        Thread.new { client.subscribers.retrieve(i.even? ? "sub_1" : "sub_2").id }
      end.map(&:value)

      expect(results.count("sub_1")).to eq(10)
      expect(results.count("sub_2")).to eq(10)
    end

    it "keeps value objects independent across concurrent parses" do
      stub_request(:get, "#{base}/subscribers").to_return(
        status: 200, body: list_json([{ "id" => "a" }, { "id" => "b" }])
      )

      pages = 8.times.map { Thread.new { client.subscribers.list.items.map(&:id) } }.map(&:value)

      expect(pages).to all(eq(%w[a b]))
    end
  end

  describe "frozen client cannot be reconfigured mid-flight" do
    it "raises rather than silently accepting a mutation" do
      expect { client.instance_variable_set(:@api_key, "other") }.to raise_error(FrozenError)
    end
  end

  # Value objects are immutable, but that must not be achieved by freezing data
  # the caller still owns. `.from` is public, so freezing its argument would
  # break a caller who reuses the hash afterwards.
  describe ".from does not freeze the caller's data" do
    it "leaves a subscriber payload mutable" do
      payload = { "id" => "sub_1", "email" => "a@b.com" }

      Flodesk::Subscriber.from(payload)

      expect(payload).not_to be_frozen
      expect { payload["extra"] = 1 }.not_to raise_error
    end

    it "leaves a nested custom_fields hash mutable" do
      custom_fields = { "tier" => "gold" }
      Flodesk::Subscriber.from({ "id" => "s", "custom_fields" => custom_fields })

      expect(custom_fields).not_to be_frozen
    end

    it "leaves a nested segments array mutable" do
      segments = [{ "id" => "seg_1" }]
      Flodesk::Subscriber.from({ "id" => "s", "segments" => segments })

      expect(segments).not_to be_frozen
    end

    it "leaves a webhook events array mutable" do
      events = ["subscriber.created"]
      Flodesk::Webhook.from({ "id" => "w", "events" => events })

      expect(events).not_to be_frozen
    end

    it "leaves a page payload mutable" do
      payload = { "meta" => { "page" => 1 }, "data" => [{ "id" => "a" }] }

      Flodesk::Page.from(payload, klass: Flodesk::Subscriber)

      expect(payload).not_to be_frozen
    end

    it "leaves a batch payload mutable" do
      payload = { "successes" => [], "failures" => [] }

      Flodesk::BatchResult.from(payload)

      expect(payload).not_to be_frozen
    end

    it "still exposes an immutable view through the object" do
      payload = { "id" => "sub_1" }
      subscriber = Flodesk::Subscriber.from(payload)

      expect(subscriber).to be_frozen
      expect(subscriber.to_h).to be_frozen
    end

    it "does not see later caller mutations reflected in the object" do
      payload = { "id" => "sub_1", "email" => "a@b.com" }
      subscriber = Flodesk::Subscriber.from(payload)

      payload["email"] = "changed@b.com"

      expect(subscriber.to_h["email"]).to eq("a@b.com")
    end
  end
end
