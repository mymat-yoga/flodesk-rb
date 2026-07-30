# frozen_string_literal: true

RSpec.describe Flodesk::Resources::Segments do
  let(:base) { "https://example.test/v1" }
  let(:client) { Flodesk::Client.new(api_key: "k", base_url: base, backoff_base: 0) }
  let(:segments) { client.segments }
  let(:segment_json) { { "id" => "seg_1", "name" => "VIPs", "color" => "#ffeecc" }.to_json }

  describe "#list" do
    it "issues GET /segments and returns a page of Segment objects" do
      stub_request(:get, "#{base}/segments").to_return(
        status: 200, body: { "meta" => { "page" => 1 }, "data" => [{ "id" => "seg_1" }] }.to_json
      )

      page = segments.list

      expect(page.items).to all(be_a(Flodesk::Segment))
    end

    it "returns an empty page when the account has no segments" do
      stub_request(:get, "#{base}/segments").to_return(
        status: 200, body: { "meta" => { "page" => 1, "total_items" => 0 }, "data" => [] }.to_json
      )

      expect(segments.list).to be_empty
    end
  end

  describe "#retrieve" do
    it "issues GET /segments/{id}" do
      stub_request(:get, "#{base}/segments/seg_1").to_return(status: 200, body: segment_json)

      expect(segments.retrieve("seg_1").name).to eq("VIPs")
    end

    it "raises NotFoundError when the segment does not exist" do
      stub_request(:get, "#{base}/segments/nope").to_return(status: 404, body: "{}")

      expect { segments.retrieve("nope") }.to raise_error(Flodesk::NotFoundError)
    end
  end

  describe "#create" do
    it "issues POST /segments and returns the created Segment from a 201" do
      req = stub_request(:post, "#{base}/segments")
            .with(body: { "name" => "VIPs" }).to_return(status: 201, body: segment_json)

      expect(segments.create(name: "VIPs").id).to eq("seg_1")
      expect(req).to have_been_requested
    end

    it "sends an optional color" do
      req = stub_request(:post, "#{base}/segments")
            .with(body: { "name" => "VIPs", "color" => "#ffeecc" })
            .to_return(status: 201, body: segment_json)

      segments.create(name: "VIPs", color: "#ffeecc")

      expect(req).to have_been_requested
    end

    it "requires a name" do
      expect { segments.create(name: nil) }.to raise_error(ArgumentError, /name/)
      expect(a_request(:post, "#{base}/segments")).not_to have_been_made
    end

    # These three are the whole point of declaring this endpoint
    # non-idempotent: a retry would create a second, duplicate segment.
    it "is NOT retried on a server error" do
      req = stub_request(:post, "#{base}/segments").to_return(status: 503, body: "{}")

      expect { segments.create(name: "VIPs") }.to raise_error(Flodesk::ServerError)
      expect(req).to have_been_requested.once
    end

    it "is NOT retried after a timeout, since the segment may in fact exist" do
      req = stub_request(:post, "#{base}/segments").to_timeout

      expect { segments.create(name: "VIPs") }.to raise_error(Flodesk::TimeoutError)
      expect(req).to have_been_requested.once
    end

    it "is NOT retried on a connection reset" do
      req = stub_request(:post, "#{base}/segments").to_raise(Errno::ECONNRESET)

      expect { segments.create(name: "VIPs") }.to raise_error(Flodesk::ConnectionError)
      expect(req).to have_been_requested.once
    end

    it "raises BadRequestError without retrying on a 400" do
      req = stub_request(:post, "#{base}/segments").to_return(status: 400, body: "{}")

      expect { segments.create(name: "VIPs") }.to raise_error(Flodesk::BadRequestError)
      expect(req).to have_been_requested.once
    end
  end

  describe "#colors" do
    it "issues GET /segments/colors" do
      req = stub_request(:get, "#{base}/segments/colors")
            .to_return(status: 200, body: { "data" => ["#ffeecc"] }.to_json)

      segments.colors

      expect(req).to have_been_requested
    end

    it "raises AuthenticationError on a 401, the only error this endpoint documents" do
      stub_request(:get, "#{base}/segments/colors").to_return(status: 401, body: "{}")

      expect { segments.colors }.to raise_error(Flodesk::AuthenticationError)
    end
  end
end
