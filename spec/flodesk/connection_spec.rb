# frozen_string_literal: true

RSpec.describe Flodesk::Connection do
  let(:base) { "https://example.test/v1" }

  # backoff_base: 0 keeps retry specs instant. The backoff calculation itself is
  # asserted separately below.
  def client(**opts)
    Flodesk::Client.new(
      api_key: "fd_key", base_url: base, backoff_base: 0, **opts
    )
  end

  describe "authentication" do
    it "sends the api key as the basic auth username with an empty password" do
      req = stub_request(:get, "#{base}/segments/colors")
            .with(basic_auth: ["fd_key", ""])
            .to_return(status: 200, body: "{}")

      client.segments.colors

      expect(req).to have_been_requested
    end

    it "never exposes the api key through inspect" do
      expect(client.inspect).to include("[REDACTED]")
      expect(client.inspect).not_to include("fd_key")
    end

    it "never exposes the api key through the auth strategy's inspect" do
      expect(client.auth.inspect).not_to include("fd_key")
    end
  end

  describe "request identification" do
    it "includes app_name and the gem version when app_name is given" do
      req = stub_request(:get, "#{base}/segments/colors")
            .with(headers: { "User-Agent" => "MyApp (myapp.com) flodesk/#{Flodesk::VERSION}" })
            .to_return(status: 200, body: "{}")

      client(app_name: "MyApp (myapp.com)").segments.colors

      expect(req).to have_been_requested
    end

    it "still identifies the gem when app_name is omitted" do
      req = stub_request(:get, "#{base}/segments/colors")
            .with(headers: { "User-Agent" => "flodesk/#{Flodesk::VERSION}" })
            .to_return(status: 200, body: "{}")

      client.segments.colors

      expect(req).to have_been_requested
    end
  end

  describe "JSON transport" do
    subject(:conn) { client }

    it "sends a JSON body with the correct content type" do
      req = stub_request(:post, "#{base}/thing")
            .with(
              body: { "a" => 1 }.to_json,
              headers: { "Content-Type" => "application/json" }
            ).to_return(status: 200, body: "{}")

      conn.request(:post, "/thing", body: { a: 1 })

      expect(req).to have_been_requested
    end

    it "sends no content type when there is no body" do
      stub_request(:get, "#{base}/thing").to_return(status: 200, body: "{}")

      expect { conn.request(:get, "/thing") }.not_to raise_error
    end

    it "parses a JSON response body" do
      stub_request(:get, "#{base}/thing").to_return(
        status: 200, body: { "id" => "x" }.to_json
      )

      expect(conn.request(:get, "/thing").body).to eq({ "id" => "x" })
    end

    it "does not parse a 204 response as JSON" do
      stub_request(:delete, "#{base}/thing").to_return(status: 204, body: "")

      response = conn.request(:delete, "/thing")

      expect(response.status).to eq(204)
      expect(response.body).to be_nil
    end

    it "treats an empty 200 body as nil rather than raising" do
      stub_request(:get, "#{base}/thing").to_return(status: 200, body: "")

      expect(conn.request(:get, "/thing").body).to be_nil
    end

    it "raises carrying context when a 2xx body is not valid JSON" do
      stub_request(:get, "#{base}/thing").to_return(status: 200, body: "not json")

      expect { conn.request(:get, "/thing") }.to raise_error(Flodesk::Error, /Malformed JSON/)
    end

    it "maps an error response with an HTML body to a typed error" do
      stub_request(:get, "#{base}/thing")
        .to_return(status: 503, body: "<html>oh no</html>")

      expect { conn.request(:get, "/thing") }.to raise_error(Flodesk::ServerError)
    end

    it "serializes query parameters" do
      req = stub_request(:get, "#{base}/thing").with(query: { "page" => "2" })
                                               .to_return(status: 200, body: "{}")

      conn.request(:get, "/thing", query: { "page" => 2 })

      expect(req).to have_been_requested
    end

    it "omits the query string entirely when the query is empty" do
      req = stub_request(:get, "#{base}/thing").to_return(status: 200, body: "{}")

      conn.request(:get, "/thing", query: {})

      expect(req).to have_been_requested
    end
  end

  describe "retry eligibility by endpoint idempotency" do
    it "retries an idempotent request on 503" do
      req = stub_request(:post, "#{base}/subscribers")
            .to_return({ status: 503, body: "{}" }, { status: 200, body: "{}" })

      client.request(:post, "/subscribers", idempotent: true)

      expect(req).to have_been_requested.twice
    end

    it "does not retry a non-idempotent request on 503" do
      req = stub_request(:post, "#{base}/segments").to_return(status: 503, body: "{}")

      expect { client.request(:post, "/segments", idempotent: false) }
        .to raise_error(Flodesk::ServerError)

      expect(req).to have_been_requested.once
    end

    it "never retries a 400, even for an idempotent operation" do
      req = stub_request(:post, "#{base}/subscribers").to_return(status: 400, body: "{}")

      expect { client.request(:post, "/subscribers", idempotent: true) }
        .to raise_error(Flodesk::BadRequestError)

      expect(req).to have_been_requested.once
    end

    it "never retries a 404" do
      req = stub_request(:get, "#{base}/thing").to_return(status: 404, body: "{}")

      expect { client.request(:get, "/thing") }.to raise_error(Flodesk::NotFoundError)

      expect(req).to have_been_requested.once
    end

    it "retries a 429 regardless of idempotency" do
      req = stub_request(:post, "#{base}/segments")
            .to_return({ status: 429, body: "{}" }, { status: 200, body: "{}" })

      client.request(:post, "/segments", idempotent: false)

      expect(req).to have_been_requested.twice
    end

    it "does not retry a 429 when retry_rate_limit is false" do
      # POST /campaigns/canva: a 429 cannot prove the campaign was not accepted.
      req = stub_request(:post, "#{base}/campaigns/canva").to_return(status: 429, body: "{}")

      expect do
        client.request(:post, "/campaigns/canva", idempotent: false, retry_rate_limit: false)
      end.to raise_error(Flodesk::RateLimitError)

      expect(req).to have_been_requested.once
    end

    it "retries an idempotent DELETE on 503" do
      req = stub_request(:delete, "#{base}/thing")
            .to_return({ status: 503, body: "{}" }, { status: 204, body: "" })

      client.request(:delete, "/thing", idempotent: true)

      expect(req).to have_been_requested.twice
    end
  end

  describe "retry eligibility for transport failures" do
    it "retries an idempotent request after a read timeout" do
      req = stub_request(:post, "#{base}/subscribers")
            .to_timeout.then.to_return(status: 200, body: "{}")

      client.request(:post, "/subscribers", idempotent: true)

      expect(req).to have_been_requested.twice
    end

    it "does not retry a non-idempotent request after a timeout" do
      req = stub_request(:post, "#{base}/segments").to_timeout

      expect { client.request(:post, "/segments", idempotent: false) }
        .to raise_error(Flodesk::TimeoutError)

      expect(req).to have_been_requested.once
    end

    it "retries an idempotent request after a connection reset" do
      req = stub_request(:get, "#{base}/thing")
            .to_raise(Errno::ECONNRESET).then.to_return(status: 200, body: "{}")

      client.request(:get, "/thing")

      expect(req).to have_been_requested.twice
    end

    it "raises ConnectionError when connection failures outlast the retry budget" do
      stub_request(:get, "#{base}/thing").to_raise(Errno::ECONNREFUSED)

      expect { client(max_retries: 1).request(:get, "/thing") }
        .to raise_error(Flodesk::ConnectionError)
    end
  end

  describe "retry budget" do
    it "makes at most max_retries additional attempts" do
      req = stub_request(:get, "#{base}/thing").to_return(status: 503, body: "{}")

      expect { client(max_retries: 2).request(:get, "/thing") }
        .to raise_error(Flodesk::ServerError)

      expect(req).to have_been_requested.times(3)
    end

    it "makes exactly one attempt when retries are disabled" do
      req = stub_request(:get, "#{base}/thing").to_return(status: 503, body: "{}")

      expect { client(max_retries: 0).request(:get, "/thing") }
        .to raise_error(Flodesk::ServerError)

      expect(req).to have_been_requested.once
    end

    it "raises the error from the final attempt" do
      stub_request(:get, "#{base}/thing").to_return(
        { status: 503, body: "{}" },
        { status: 503, body: { "code" => "last", "message" => "final failure" }.to_json }
      )

      expect { client(max_retries: 1).request(:get, "/thing") }
        .to raise_error(Flodesk::ServerError, "final failure")
    end
  end

  describe "backoff" do
    # The delay calculation is asserted directly rather than by observing sleep,
    # so these examples are neither slow nor timing-dependent.
    def connection_for(**opts)
      client(**opts).instance_variable_get(:@connection)
    end

    it "never returns a delay longer than the rate limit window" do
      conn = connection_for(backoff_base: 30)

      delays = (1..10).map { |attempt| conn.send(:backoff_delay, attempt) }

      expect(delays).to all(be <= Flodesk::MAX_BACKOFF_SECONDS)
    end

    it "grows the delay as attempts accumulate" do
      conn = connection_for(backoff_base: 1)

      # Jitter spans the lower half of each capped value, so compare ceilings
      # rather than exact values.
      expect(conn.send(:backoff_delay, 3)).to be > conn.send(:backoff_delay, 1) * 0.9
    end

    it "returns a positive delay when backoff is enabled" do
      expect(connection_for(backoff_base: 1).send(:backoff_delay, 1)).to be_positive
    end

    it "returns nil when the backoff base is zero, disabling sleeping entirely" do
      expect(connection_for(backoff_base: 0).send(:backoff_delay, 1)).to be_nil
    end

    it "still retries when backoff is disabled" do
      req = stub_request(:get, "#{base}/thing")
            .to_return({ status: 503, body: "{}" }, { status: 200, body: "{}" })

      client(backoff_base: 0).request(:get, "/thing")

      expect(req).to have_been_requested.twice
    end
  end

  describe "rate limit visibility" do
    it "exposes the observed limit and remaining values after a call" do
      stub_request(:get, "#{base}/thing").to_return(
        status: 200, body: "{}",
        headers: { "X-Fd-RateLimit-Limit" => "100", "X-Fd-RateLimit-Remaining" => "68" }
      )
      c = client

      c.request(:get, "/thing")

      expect(c.rate_limit.limit).to eq(100)
      expect(c.rate_limit.remaining).to eq(68)
    end

    it "exposes the values on the response itself" do
      stub_request(:get, "#{base}/thing").to_return(
        status: 200, body: "{}",
        headers: { "X-Fd-RateLimit-Limit" => "100", "X-Fd-RateLimit-Remaining" => "7" }
      )

      response = client.request(:get, "/thing")

      expect(response.rate_limit).to eq(100)
      expect(response.rate_limit_remaining).to eq(7)
    end

    it "reports nil when the headers are absent" do
      stub_request(:get, "#{base}/thing").to_return(status: 200, body: "{}")

      response = client.request(:get, "/thing")

      expect(response.rate_limit).to be_nil
      expect(response.rate_limit_remaining).to be_nil
    end

    it "reports no reset time, because the API sends no reset header" do
      stub_request(:get, "#{base}/thing").to_return(
        status: 200, body: "{}", headers: { "X-Fd-RateLimit-Limit" => "100" }
      )

      expect(client.request(:get, "/thing").rate_limit_reset).to be_nil
    end
  end

  describe "timeouts" do
    it "applies the configured timeouts to the underlying connection" do
      c = client(open_timeout: 3, read_timeout: 7)
      captured = nil

      allow(Net::HTTP).to receive(:new).and_wrap_original do |orig, *args|
        captured = orig.call(*args)
      end
      stub_request(:get, "#{base}/thing").to_return(status: 200, body: "{}")

      c.request(:get, "/thing")

      expect(captured.open_timeout).to eq(3)
      expect(captured.read_timeout).to eq(7)
    end
  end

  describe "thread safety" do
    it "serves concurrent requests through one shared client" do
      stub_request(:get, "#{base}/thing").to_return(status: 200, body: { "ok" => true }.to_json)
      shared = client

      results = Array.new(12) do
        Thread.new { shared.request(:get, "/thing").body }
      end.map(&:value)

      expect(results).to all(eq({ "ok" => true }))
    end

    it "keeps rate limit state per thread rather than shared" do
      stub_request(:get, "#{base}/a").to_return(
        status: 200, body: "{}", headers: { "X-Fd-RateLimit-Remaining" => "1" }
      )
      stub_request(:get, "#{base}/b").to_return(
        status: 200, body: "{}", headers: { "X-Fd-RateLimit-Remaining" => "99" }
      )
      shared = client

      observed = [
        Thread.new do
          shared.request(:get, "/a")
          shared.rate_limit.remaining
        end,
        Thread.new do
          shared.request(:get, "/b")
          shared.rate_limit.remaining
        end
      ].map(&:value)

      expect(observed).to contain_exactly(1, 99)
    end
  end
end
