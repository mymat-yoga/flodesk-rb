# frozen_string_literal: true

RSpec.describe Flodesk::Client do
  describe "construction" do
    it "builds a client from an api key" do
      client = described_class.new(api_key: "fd_key")

      expect(client).to be_a(described_class)
    end

    it "raises ArgumentError when api_key is omitted, not on first request" do
      expect { described_class.new }.to raise_error(ArgumentError, /api_key/)
    end

    it "raises ArgumentError when api_key is nil" do
      expect { described_class.new(api_key: nil) }.to raise_error(ArgumentError, /api_key/)
    end

    it "raises ArgumentError when api_key is empty" do
      expect { described_class.new(api_key: "  ") }.to raise_error(ArgumentError, /api_key/)
    end

    it "defaults to the production base url" do
      expect(described_class.new(api_key: "k").base_url).to eq(Flodesk::DEFAULT_BASE_URL)
    end

    it "accepts an explicit base_url so the suite can target a stub host" do
      client = described_class.new(api_key: "k", base_url: "https://example.test/v1")

      expect(client.base_url).to eq("https://example.test/v1")
    end

    it "freezes the client so configuration cannot drift after construction" do
      expect(described_class.new(api_key: "k")).to be_frozen
    end

    it "freezes the api key string" do
      expect(described_class.new(api_key: +"k").api_key).to be_frozen
    end

    it "applies finite default timeouts" do
      client = described_class.new(api_key: "k")

      expect(client.open_timeout).to be_a(Numeric).and be_positive
      expect(client.read_timeout).to be_a(Numeric).and be_positive
    end

    it "accepts explicit timeouts" do
      client = described_class.new(api_key: "k", open_timeout: 1, read_timeout: 2)

      expect(client.open_timeout).to eq(1)
      expect(client.read_timeout).to eq(2)
    end

    it "defaults to a nonzero retry budget" do
      expect(described_class.new(api_key: "k").max_retries).to be_positive
    end

    it "accepts zero retries to disable retrying entirely" do
      expect(described_class.new(api_key: "k", max_retries: 0).max_retries).to eq(0)
    end

    it "rejects a negative retry budget" do
      expect { described_class.new(api_key: "k", max_retries: -1) }
        .to raise_error(ArgumentError, /max_retries/)
    end
  end

  describe "isolation between clients" do
    it "keeps credentials separate" do
      a = described_class.new(api_key: "key_a")
      b = described_class.new(api_key: "key_b")

      expect(a.api_key).to eq("key_a")
      expect(b.api_key).to eq("key_b")
    end

    it "sends each client's own credentials" do
      a = described_class.new(api_key: "key_a", base_url: "https://example.test/v1")
      b = described_class.new(api_key: "key_b", base_url: "https://example.test/v1")

      req_a = stub_request(:get, "https://example.test/v1/segments/colors")
              .with(basic_auth: %w[key_a]).to_return(status: 200, body: "{}")
      req_b = stub_request(:get, "https://example.test/v1/segments/colors")
              .with(basic_auth: %w[key_b]).to_return(status: 200, body: "{}")

      a.segments.colors
      b.segments.colors

      expect(req_a).to have_been_requested
      expect(req_b).to have_been_requested
    end
  end

  describe "resource namespaces" do
    subject(:client) { described_class.new(api_key: "k") }

    it "exposes every resource namespace" do
      expect(client.subscribers).to be_a(Flodesk::Resources::Subscribers)
      expect(client.segments).to be_a(Flodesk::Resources::Segments)
      expect(client.custom_fields).to be_a(Flodesk::Resources::CustomFields)
      expect(client.workflows).to be_a(Flodesk::Resources::Workflows)
      expect(client.webhooks).to be_a(Flodesk::Resources::Webhooks)
      expect(client.campaigns).to be_a(Flodesk::Resources::Campaigns)
    end

    it "returns a memoized namespace so repeated access is cheap" do
      expect(client.subscribers).to be(client.subscribers)
    end
  end

  describe "no global state" do
    it "does not expose a module-level configure hook" do
      expect(Flodesk).not_to respond_to(:configure)
    end

    it "does not expose a module-level default client" do
      expect(Flodesk).not_to respond_to(:client)
    end
  end
end
