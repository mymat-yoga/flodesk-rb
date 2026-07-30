# frozen_string_literal: true

# Flodesk treats any 2XX as "delivered" and anything else as "retry later", so
# the status a handler produces is the only backpressure signal available.
RSpec.describe "Flodesk::Webhooks::Handler#respond" do
  let(:token) { "t" * 32 }
  let(:handler) { Flodesk::Webhooks::Handler.new(token: token) }

  let(:payload) do
    {
      "event_name" => "subscriber.created",
      "event_time" => "2023-01-02T15:04:05.999Z",
      "webhook_id" => "wh_1",
      "subscriber" => { "id" => "sub_1", "email" => "a@b.com" }
    }
  end

  def body = JSON.generate(payload)

  it "returns 200 when the event is verified, parsed and handled" do
    status, = handler.respond(body: body, token: token) { |_event| :ok }

    expect(status).to eq(200)
  end

  it "yields the parsed event to the block" do
    seen = nil

    handler.respond(body: body, token: token) { |event| seen = event }

    expect(seen).to be_a(Flodesk::Webhooks::Event)
    expect(seen.subscriber.id).to eq("sub_1")
  end

  it "returns 200 with no block, treating receipt alone as acknowledgement" do
    status, = handler.respond(body: body, token: token)

    expect(status).to eq(200)
  end

  it "returns 401 when verification fails" do
    status, = handler.respond(body: body, token: "wrong") { |_| :ok }

    expect(status).to eq(401)
  end

  it "does not invoke the block when verification fails" do
    called = false

    handler.respond(body: body, token: "wrong") { |_| called = true }

    expect(called).to be(false)
  end

  it "returns 400 when the payload is unparseable" do
    status, = handler.respond(body: "{nope", token: token) { |_| :ok }

    expect(status).to eq(400)
  end

  it "returns 500 when the application's handler raises, so Flodesk retries" do
    status, = handler.respond(body: body, token: token) { |_| raise "boom" }

    expect(status).to eq(500)
  end

  it "never returns 2XX for a rejected request" do
    [
      handler.respond(body: body, token: "wrong") { |_| :ok },
      handler.respond(body: "{nope", token: token) { |_| :ok },
      handler.respond(body: body, token: token) { |_| raise "boom" }
    ].each { |status, _| expect(status).not_to be_between(200, 299) }
  end

  it "returns a Rack-compatible triple" do
    status, headers, rack_body = handler.respond(body: body, token: token) { |_| :ok }

    expect(status).to be_a(Integer)
    expect(headers).to be_a(Hash)
    expect(rack_body).to be_an(Array)
  end

  it "keeps PII out of the response body on failure" do
    _, _, rack_body = handler.respond(body: body, token: "wrong") { |_| :ok }

    expect(rack_body.join).not_to include("a@b.com")
    expect(rack_body.join).not_to include(token)
  end

  it "does not swallow the application's exception silently" do
    # The application must be able to observe its own failures.
    captured = nil

    handler.respond(body: body, token: token, on_error: ->(e) { captured = e }) do |_|
      raise ArgumentError, "boom"
    end

    expect(captured).to be_a(ArgumentError)
  end
end
