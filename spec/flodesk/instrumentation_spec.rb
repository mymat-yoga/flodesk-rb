# frozen_string_literal: true

require "active_support"
require "active_support/notifications"

RSpec.describe "flodesk.request instrumentation" do
  let(:base) { "https://example.test/v1" }
  let(:client) { Flodesk::Client.new(api_key: "k", base_url: base, backoff_base: 0) }

  # Collects every flodesk.request event emitted during the block.
  def capture_events
    events = []
    subscriber = ActiveSupport::Notifications.subscribe("flodesk.request") do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end
    yield
    events
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  it "emits an event for a successful request" do
    stub_request(:get, "#{base}/segments/colors").to_return(status: 200, body: "{}")

    events = capture_events { client.segments.colors }

    expect(events.size).to eq(1)
    expect(events.first.name).to eq("flodesk.request")
  end

  it "records method, endpoint and status" do
    stub_request(:get, "#{base}/segments/colors").to_return(status: 200, body: "{}")

    events = capture_events { client.segments.colors }

    expect(events.first.payload[:method]).to eq("GET")
    expect(events.first.payload[:endpoint]).to eq("/segments/colors")
    expect(events.first.payload[:status]).to eq(200)
  end

  it "records a duration" do
    stub_request(:get, "#{base}/segments/colors").to_return(status: 200, body: "{}")

    events = capture_events { client.segments.colors }

    expect(events.first.payload[:duration]).to be_a(Numeric)
  end

  it "records rate limit remaining when the header is present" do
    stub_request(:get, "#{base}/segments/colors").to_return(
      status: 200, body: "{}", headers: { "X-Fd-RateLimit-Remaining" => "42" }
    )

    events = capture_events { client.segments.colors }

    expect(events.first.payload[:rate_limit_remaining]).to eq(42)
  end

  it "emits an event for a failed request too" do
    stub_request(:get, "#{base}/segments/colors").to_return(status: 401, body: "{}")

    events = capture_events do
      client.segments.colors
    rescue Flodesk::AuthenticationError
      nil
    end

    expect(events.size).to eq(1)
    expect(events.first.payload[:status]).to eq(401)
  end

  it "emits one event per attempt, so retries are visible" do
    stub_request(:get, "#{base}/segments/colors")
      .to_return({ status: 503, body: "{}" }, { status: 200, body: "{}" })

    events = capture_events { client.segments.colors }

    expect(events.size).to eq(2)
    expect(events.map { |e| e.payload[:status] }).to eq([503, 200])
  end

  it "reports the attempt number" do
    stub_request(:get, "#{base}/segments/colors")
      .to_return({ status: 503, body: "{}" }, { status: 200, body: "{}" })

    events = capture_events { client.segments.colors }

    expect(events.map { |e| e.payload[:attempt] }).to eq([1, 2])
  end

  describe "PII redaction" do
    it "redacts an email address embedded in the request path" do
      stub_request(:get, "#{base}/subscribers/a%40b.com").to_return(
        status: 200, body: { "id" => "sub_1" }.to_json
      )

      events = capture_events { client.subscribers.retrieve("a@b.com") }

      endpoint = events.first.payload[:endpoint]
      expect(endpoint).not_to include("a@b.com")
      expect(endpoint).not_to include("a%40b.com")
      expect(endpoint).to include("REDACTED")
    end

    it "does not include the request body in the payload" do
      stub_request(:post, "#{base}/subscribers").to_return(
        status: 200, body: { "id" => "sub_1" }.to_json
      )

      events = capture_events do
        client.subscribers.upsert(
          email: "a@b.com", custom_fields: { "tier" => "gold" }, optin_ip: "203.0.113.5"
        )
      end

      serialized = events.first.payload.inspect
      expect(serialized).not_to include("a@b.com")
      expect(serialized).not_to include("203.0.113.5")
      expect(serialized).not_to include("gold")
    end

    it "does not include the response body in the payload" do
      stub_request(:get, "#{base}/subscribers/sub_1").to_return(
        status: 200,
        body: { "id" => "sub_1", "email" => "a@b.com", "optin_ip" => "203.0.113.5" }.to_json
      )

      events = capture_events { client.subscribers.retrieve("sub_1") }

      serialized = events.first.payload.inspect
      expect(serialized).not_to include("a@b.com")
      expect(serialized).not_to include("203.0.113.5")
    end

    it "does not include the api key in the payload" do
      stub_request(:get, "#{base}/segments/colors").to_return(status: 200, body: "{}")

      events = capture_events { client.segments.colors }

      expect(events.first.payload.inspect).not_to include("fd_key")
    end

    it "keeps the subscriber id, which is a safe handle" do
      stub_request(:get, "#{base}/subscribers/sub_1").to_return(
        status: 200, body: { "id" => "sub_1" }.to_json
      )

      events = capture_events { client.subscribers.retrieve("sub_1") }

      expect(events.first.payload[:endpoint]).to eq("/subscribers/sub_1")
    end
  end

  describe "when ActiveSupport is unavailable" do
    # ActiveSupport is a development dependency here, so its absence is
    # simulated. The gem must never require it at runtime.
    before { allow(Flodesk::Instrumentation).to receive(:available?).and_return(false) }

    it "still completes requests successfully" do
      stub_request(:get, "#{base}/segments/colors").to_return(status: 200, body: "{}")

      expect { client.segments.colors }.not_to raise_error
    end

    it "emits no notifications" do
      stub_request(:get, "#{base}/segments/colors").to_return(status: 200, body: "{}")

      events = capture_events { client.segments.colors }

      expect(events).to be_empty
    end
  end

  describe "runtime dependencies" do
    it "declares no runtime dependencies at all" do
      spec = Gem::Specification.load("flodesk-rb.gemspec")

      expect(spec.runtime_dependencies).to be_empty
    end
  end
end
