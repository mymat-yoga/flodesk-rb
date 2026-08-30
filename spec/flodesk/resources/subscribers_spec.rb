# frozen_string_literal: true

RSpec.describe Flodesk::Resources::Subscribers do
  let(:base) { "https://example.test/v1" }
  let(:client) { Flodesk::Client.new(api_key: "k", base_url: base, backoff_base: 0) }
  let(:subscribers) { client.subscribers }

  let(:subscriber_json) do
    { "id" => "sub_1", "email" => "a@b.com", "status" => "active" }.to_json
  end

  describe "#list" do
    it "issues GET /subscribers and returns a page of Subscriber objects" do
      stub_request(:get, "#{base}/subscribers").to_return(
        status: 200,
        body: { "meta" => { "page" => 1 }, "data" => [{ "id" => "sub_1" }] }.to_json
      )

      page = subscribers.list

      expect(page).to be_a(Flodesk::Page)
      expect(page.items).to all(be_a(Flodesk::Subscriber))
    end

    it "filters by status" do
      req = stub_request(:get, "#{base}/subscribers")
            .with(query: { "status" => "unsubscribed" })
            .to_return(status: 200, body: { "data" => [] }.to_json)

      subscribers.list(status: :unsubscribed)

      expect(req).to have_been_requested
    end

    it "filters by segment_id" do
      req = stub_request(:get, "#{base}/subscribers")
            .with(query: { "segment_id" => "seg_1" })
            .to_return(status: 200, body: { "data" => [] }.to_json)

      subscribers.list(segment_id: "seg_1")

      expect(req).to have_been_requested
    end

    it "filters by status and segment together" do
      req = stub_request(:get, "#{base}/subscribers")
            .with(query: { "status" => "active", "segment_id" => "seg_1" })
            .to_return(status: 200, body: { "data" => [] }.to_json)

      subscribers.list(status: :active, segment_id: "seg_1")

      expect(req).to have_been_requested
    end

    it "rejects a status outside the documented enum before any request" do
      expect { subscribers.list(status: :hibernating) }
        .to raise_error(ArgumentError, /status/)

      expect(a_request(:get, "#{base}/subscribers")).not_to have_been_made
    end

    # Every documented status must be filterable. A value missing from the enum
    # is not a harmless omission: validate_enum! turns it into a client-side
    # ArgumentError, making a working endpoint unreachable.
    it "accepts every documented subscriber status" do
      Flodesk::Enums::SUBSCRIBER_STATUSES.each do |status|
        stub_request(:get, "#{base}/subscribers")
          .with(query: { "status" => status })
          .to_return(status: 200, body: { "data" => [] }.to_json)

        expect { subscribers.list(status: status) }.not_to raise_error
      end
    end

    it "filters by the archived status" do
      req = stub_request(:get, "#{base}/subscribers")
            .with(query: { "status" => "archived" })
            .to_return(status: 200, body: { "data" => [] }.to_json)

      subscribers.list(status: :archived)

      expect(req).to have_been_requested
    end
  end

  describe "#retrieve" do
    it "retrieves by id" do
      stub_request(:get, "#{base}/subscribers/sub_1").to_return(status: 200, body: subscriber_json)

      expect(subscribers.retrieve("sub_1").id).to eq("sub_1")
    end

    it "retrieves by email" do
      stub_request(:get, "#{base}/subscribers/a%40b.com")
        .to_return(status: 200, body: subscriber_json)

      expect(subscribers.retrieve("a@b.com").email).to eq("a@b.com")
    end

    it "percent-encodes an email containing a plus sign" do
      # If "+" reached the API unencoded it would be read as a space, silently
      # addressing the wrong subscriber.
      req = stub_request(:get, "#{base}/subscribers/a%2Btag%40b.com")
            .to_return(status: 200, body: subscriber_json)

      subscribers.retrieve("a+tag@b.com")

      expect(req).to have_been_requested
    end

    it "raises NotFoundError when the subscriber does not exist" do
      stub_request(:get, "#{base}/subscribers/nope").to_return(status: 404, body: "{}")

      expect { subscribers.retrieve("nope") }.to raise_error(Flodesk::NotFoundError)
    end

    it "rejects a blank identifier without making a request" do
      expect { subscribers.retrieve("") }.to raise_error(ArgumentError)
      expect { subscribers.retrieve(nil) }.to raise_error(ArgumentError)
    end
  end

  describe "#upsert" do
    it "issues POST /subscribers and returns the resulting Subscriber" do
      req = stub_request(:post, "#{base}/subscribers")
            .with(body: { "email" => "a@b.com" })
            .to_return(status: 200, body: subscriber_json)

      expect(subscribers.upsert(email: "a@b.com").id).to eq("sub_1")
      expect(req).to have_been_requested
    end

    it "sends every documented writable field" do
      req = stub_request(:post, "#{base}/subscribers")
            .with(
              body: {
                "email" => "a@b.com", "first_name" => "Ada", "last_name" => "L",
                "segment_ids" => %w[seg_1], "double_optin" => true,
                "custom_fields" => { "tier" => "gold" },
                "optin_ip" => "203.0.113.5",
                "optin_timestamp" => "2023-01-02T15:04:05.999Z"
              }
            ).to_return(status: 200, body: subscriber_json)

      subscribers.upsert(
        email: "a@b.com", first_name: "Ada", last_name: "L",
        segment_ids: %w[seg_1], double_optin: true,
        custom_fields: { "tier" => "gold" },
        optin_ip: "203.0.113.5", optin_timestamp: "2023-01-02T15:04:05.999Z"
      )

      expect(req).to have_been_requested
    end

    it "accepts an id instead of an email" do
      req = stub_request(:post, "#{base}/subscribers")
            .with(body: { "id" => "sub_1" }).to_return(status: 200, body: subscriber_json)

      subscribers.upsert(id: "sub_1")

      expect(req).to have_been_requested
    end

    it "omits fields the caller did not supply" do
      req = stub_request(:post, "#{base}/subscribers")
            .with(body: { "email" => "a@b.com" }).to_return(status: 200, body: subscriber_json)

      subscribers.upsert(email: "a@b.com")

      expect(req).to have_been_requested
    end

    # Previously an unrecognized key was silently dropped: `frist_name:` simply
    # vanished and the request succeeded, reporting nothing. Rejecting is only
    # safe because the contract spec now verifies SUBSCRIBER_FIELDS against the
    # CreateOrUpdateSubscriberItem schema — a field Flodesk adds fails the build
    # rather than becoming an unexplained runtime rejection.
    it "raises on an unknown attribute rather than silently dropping it" do
      expect { subscribers.upsert(email: "a@b.com", frist_name: "Ada") }
        .to raise_error(ArgumentError, /frist_name/)

      expect(a_request(:post, "#{base}/subscribers")).not_to have_been_made
    end

    it "names every unknown attribute, not just the first" do
      expect { subscribers.upsert(email: "a@b.com", nope: 1, also_nope: 2) }
        .to raise_error(ArgumentError, /also_nope/)
    end

    it "accepts string keys as readily as symbols" do
      req = stub_request(:post, "#{base}/subscribers")
            .with(body: { "email" => "a@b.com", "first_name" => "Ada" })
            .to_return(status: 200, body: subscriber_json)

      subscribers.upsert("email" => "a@b.com", "first_name" => "Ada")

      expect(req).to have_been_requested
    end

    it "accepts every field the specification documents" do
      Flodesk::Resources::Subscribers::SUBSCRIBER_FIELDS.each do |field|
        value = case field
                when :segment_ids then %w[seg_1]
                when :custom_fields then { "k" => "v" }
                when :double_optin then true
                else "x"
                end

        stub_request(:post, "#{base}/subscribers")
          .to_return(status: 200, body: subscriber_json)

        expect { subscribers.upsert(:email => "a@b.com", field => value) }
          .not_to raise_error
      end
    end

    it "raises ArgumentError when neither id nor email is given" do
      expect { subscribers.upsert(first_name: "Ada") }
        .to raise_error(ArgumentError, /email.*id|id.*email/i)

      expect(a_request(:post, "#{base}/subscribers")).not_to have_been_made
    end

    it "rejects more than fifty segment ids, which the API caps" do
      expect { subscribers.upsert(email: "a@b.com", segment_ids: Array.new(51) { |i| "s#{i}" }) }
        .to raise_error(ArgumentError, /50/)

      expect(a_request(:post, "#{base}/subscribers")).not_to have_been_made
    end

    it "accepts exactly fifty segment ids" do
      stub_request(:post, "#{base}/subscribers").to_return(status: 200, body: subscriber_json)

      expect { subscribers.upsert(email: "a@b.com", segment_ids: Array.new(50) { |i| "s#{i}" }) }
        .not_to raise_error
    end

    it "is retried on a server error, because upsert is idempotent" do
      req = stub_request(:post, "#{base}/subscribers")
            .to_return({ status: 503, body: "{}" }, { status: 200, body: subscriber_json })

      subscribers.upsert(email: "a@b.com")

      expect(req).to have_been_requested.twice
    end

    it "is not retried on a 400" do
      req = stub_request(:post, "#{base}/subscribers").to_return(status: 400, body: "{}")

      expect { subscribers.upsert(email: "a@b.com") }.to raise_error(Flodesk::BadRequestError)
      expect(req).to have_been_requested.once
    end

    describe "custom field value coercion" do
      # The API types custom_fields values as `string` only. Coercing is friendlier
      # than raising and cannot lose information, since the API would reject
      # anything else outright.
      it "coerces a boolean to a string" do
        req = stub_request(:post, "#{base}/subscribers")
              .with(body: hash_including("custom_fields" => { "vip" => "true" }))
              .to_return(status: 200, body: subscriber_json)

        subscribers.upsert(email: "a@b.com", custom_fields: { "vip" => true })

        expect(req).to have_been_requested
      end

      it "coerces an integer to a string" do
        req = stub_request(:post, "#{base}/subscribers")
              .with(body: hash_including("custom_fields" => { "orders" => "42" }))
              .to_return(status: 200, body: subscriber_json)

        subscribers.upsert(email: "a@b.com", custom_fields: { "orders" => 42 })

        expect(req).to have_been_requested
      end

      it "leaves string values untouched" do
        req = stub_request(:post, "#{base}/subscribers")
              .with(body: hash_including("custom_fields" => { "tier" => "gold" }))
              .to_return(status: 200, body: subscriber_json)

        subscribers.upsert(email: "a@b.com", custom_fields: { "tier" => "gold" })

        expect(req).to have_been_requested
      end

      it "preserves nil rather than sending the string \"\"" do
        # nil means "clear this field"; "" would be a different instruction.
        req = stub_request(:post, "#{base}/subscribers")
              .with(body: hash_including("custom_fields" => { "tier" => nil }))
              .to_return(status: 200, body: subscriber_json)

        subscribers.upsert(email: "a@b.com", custom_fields: { "tier" => nil })

        expect(req).to have_been_requested
      end

      it "stringifies symbol keys" do
        req = stub_request(:post, "#{base}/subscribers")
              .with(body: hash_including("custom_fields" => { "tier" => "gold" }))
              .to_return(status: 200, body: subscriber_json)

        subscribers.upsert(email: "a@b.com", custom_fields: { tier: :gold })

        expect(req).to have_been_requested
      end
    end
  end

  describe "#batch_upsert unknown attributes" do
    it "identifies which record carried the unknown attribute" do
      expect { subscribers.batch_upsert([{ email: "a@b.com" }, { email: "c@d.com", nope: 1 }]) }
        .to raise_error(ArgumentError, /index 1/)

      expect(a_request(:post, "#{base}/subscribers/batch")).not_to have_been_made
    end
  end

  describe "#batch_upsert" do
    let(:rows) { [{ email: "a@b.com" }, { email: "c@d.com" }] }

    def batch_body(successes: [], failures: [])
      { "successes" => successes, "failures" => failures }.to_json
    end

    it "issues POST /subscribers/batch with the records under `subscribers`" do
      req = stub_request(:post, "#{base}/subscribers/batch")
            .with(body: { "subscribers" => [{ "email" => "a@b.com" }, { "email" => "c@d.com" }] })
            .to_return(status: 200, body: batch_body(successes: [{ "id" => "s1" }, { "id" => "s2" }]))

      subscribers.batch_upsert(rows)

      expect(req).to have_been_requested
    end

    it "returns a successful BatchResult when nothing failed" do
      stub_request(:post, "#{base}/subscribers/batch")
        .to_return(status: 200, body: batch_body(successes: [{ "id" => "s1" }]))

      result = subscribers.batch_upsert(rows)

      expect(result).to be_a(Flodesk::BatchResult)
      expect(result.success?).to be(true)
    end

    it "raises PartialFailureError by default when any record failed" do
      stub_request(:post, "#{base}/subscribers/batch").to_return(
        status: 200,
        body: batch_body(
          successes: [{ "id" => "s1" }],
          failures: [{ "index" => 1, "email" => "bad@", "code" => "invalid_email" }]
        )
      )

      expect { subscribers.batch_upsert(rows) }.to raise_error(Flodesk::PartialFailureError)
    end

    it "carries the successes on the raised error, so no work is lost" do
      stub_request(:post, "#{base}/subscribers/batch").to_return(
        status: 200,
        body: batch_body(
          successes: [{ "id" => "s1" }],
          failures: [{ "index" => 1, "email" => "bad@", "code" => "invalid_email" }]
        )
      )

      begin
        subscribers.batch_upsert(rows)
      rescue Flodesk::PartialFailureError => e
        expect(e.result.successes.map(&:id)).to eq(["s1"])
        expect(e.result.failures.first.code).to eq("invalid_email")
      end
    end

    it "returns the result quietly when raise_on_failure is false" do
      stub_request(:post, "#{base}/subscribers/batch").to_return(
        status: 200,
        body: batch_body(failures: [{ "index" => 0, "code" => "invalid_email" }])
      )

      result = subscribers.batch_upsert(rows, raise_on_failure: false)

      expect(result.success?).to be(false)
      expect(result.failures.size).to eq(1)
    end

    it "rejects more than fifty records without making a request" do
      too_many = Array.new(51) { |i| { email: "a#{i}@b.com" } }

      expect { subscribers.batch_upsert(too_many) }.to raise_error(ArgumentError, /50/)
      expect(a_request(:post, "#{base}/subscribers/batch")).not_to have_been_made
    end

    it "accepts exactly fifty records" do
      stub_request(:post, "#{base}/subscribers/batch").to_return(status: 200, body: batch_body)

      expect { subscribers.batch_upsert(Array.new(50) { |i| { email: "a#{i}@b.com" } }) }
        .not_to raise_error
    end

    it "rejects an empty batch without making a request" do
      expect { subscribers.batch_upsert([]) }.to raise_error(ArgumentError, /empty/i)
      expect(a_request(:post, "#{base}/subscribers/batch")).not_to have_been_made
    end

    it "requires an id or email on every record" do
      expect { subscribers.batch_upsert([{ email: "a@b.com" }, { first_name: "Ada" }]) }
        .to raise_error(ArgumentError, /index 1/)
    end

    it "coerces custom field values on every record" do
      req = stub_request(:post, "#{base}/subscribers/batch")
            .with(
              body: {
                "subscribers" => [
                  { "email" => "a@b.com", "custom_fields" => { "vip" => "true" } }
                ]
              }
            ).to_return(status: 200, body: batch_body)

      subscribers.batch_upsert([{ email: "a@b.com", custom_fields: { "vip" => true } }])

      expect(req).to have_been_requested
    end

    it "is retried on a server error, because batch upsert is idempotent" do
      req = stub_request(:post, "#{base}/subscribers/batch")
            .to_return({ status: 503, body: "{}" }, { status: 200, body: batch_body })

      subscribers.batch_upsert(rows)

      expect(req).to have_been_requested.twice
    end

    it "raises RateLimitError after exhausting retries on 429" do
      stub_request(:post, "#{base}/subscribers/batch").to_return(status: 429, body: "{}")

      expect { subscribers.batch_upsert(rows) }.to raise_error(Flodesk::RateLimitError)
    end
  end

  describe "#add_to_segments" do
    it "issues POST /subscribers/{id}/segments with the segment ids" do
      req = stub_request(:post, "#{base}/subscribers/sub_1/segments")
            .with(body: { "segment_ids" => %w[seg_1 seg_2] })
            .to_return(status: 200, body: subscriber_json)

      subscribers.add_to_segments("sub_1", %w[seg_1 seg_2])

      expect(req).to have_been_requested
    end

    it "encodes an email identifier" do
      req = stub_request(:post, "#{base}/subscribers/a%40b.com/segments")
            .to_return(status: 200, body: subscriber_json)

      subscribers.add_to_segments("a@b.com", %w[seg_1])

      expect(req).to have_been_requested
    end

    it "succeeds when the subscriber already has the segment" do
      stub_request(:post, "#{base}/subscribers/sub_1/segments")
        .to_return(status: 200, body: subscriber_json)

      expect { subscribers.add_to_segments("sub_1", %w[seg_1]) }.not_to raise_error
    end

    it "raises NotFoundError when the subscriber does not exist" do
      stub_request(:post, "#{base}/subscribers/nope/segments").to_return(status: 404, body: "{}")

      expect { subscribers.add_to_segments("nope", %w[seg_1]) }
        .to raise_error(Flodesk::NotFoundError)
    end

    it "is retried on a server error, because adding a segment is idempotent" do
      req = stub_request(:post, "#{base}/subscribers/sub_1/segments")
            .to_return({ status: 503, body: "{}" }, { status: 200, body: subscriber_json })

      subscribers.add_to_segments("sub_1", %w[seg_1])

      expect(req).to have_been_requested.twice
    end

    it "rejects more than fifty segment ids" do
      expect { subscribers.add_to_segments("sub_1", Array.new(51) { |i| "s#{i}" }) }
        .to raise_error(ArgumentError, /50/)
    end

    it "rejects an empty segment list" do
      expect { subscribers.add_to_segments("sub_1", []) }.to raise_error(ArgumentError)
    end
  end

  describe "#remove_from_segments" do
    it "issues DELETE /subscribers/{id}/segments with the segment ids" do
      req = stub_request(:delete, "#{base}/subscribers/sub_1/segments")
            .with(body: { "segment_ids" => %w[seg_1] })
            .to_return(status: 200, body: subscriber_json)

      subscribers.remove_from_segments("sub_1", %w[seg_1])

      expect(req).to have_been_requested
    end

    it "succeeds when the subscriber does not have the segment" do
      stub_request(:delete, "#{base}/subscribers/sub_1/segments")
        .to_return(status: 200, body: subscriber_json)

      expect { subscribers.remove_from_segments("sub_1", %w[seg_9]) }.not_to raise_error
    end

    it "raises NotFoundError when the subscriber does not exist" do
      stub_request(:delete, "#{base}/subscribers/nope/segments").to_return(status: 404, body: "{}")

      expect { subscribers.remove_from_segments("nope", %w[seg_1]) }
        .to raise_error(Flodesk::NotFoundError)
    end
  end

  describe "#unsubscribe" do
    it "issues POST /subscribers/{id}/unsubscribe" do
      req = stub_request(:post, "#{base}/subscribers/sub_1/unsubscribe")
            .to_return(status: 200, body: subscriber_json)

      subscribers.unsubscribe("sub_1")

      expect(req).to have_been_requested
    end

    it "returns the updated Subscriber" do
      stub_request(:post, "#{base}/subscribers/sub_1/unsubscribe").to_return(
        status: 200,
        body: { "id" => "sub_1", "status" => "unsubscribed" }.to_json
      )

      expect(subscribers.unsubscribe("sub_1").status).to eq(:unsubscribed)
    end

    it "succeeds when the subscriber is already unsubscribed" do
      stub_request(:post, "#{base}/subscribers/sub_1/unsubscribe")
        .to_return(status: 200, body: subscriber_json)

      expect { subscribers.unsubscribe("sub_1") }.not_to raise_error
    end

    it "is retried on a server error, because unsubscribe is a terminal state" do
      req = stub_request(:post, "#{base}/subscribers/sub_1/unsubscribe")
            .to_return({ status: 503, body: "{}" }, { status: 200, body: subscriber_json })

      subscribers.unsubscribe("sub_1")

      expect(req).to have_been_requested.twice
    end

    it "encodes an email identifier" do
      req = stub_request(:post, "#{base}/subscribers/a%2Bx%40b.com/unsubscribe")
            .to_return(status: 200, body: subscriber_json)

      subscribers.unsubscribe("a+x@b.com")

      expect(req).to have_been_requested
    end
  end
end
