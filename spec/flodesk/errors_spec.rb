# frozen_string_literal: true

RSpec.describe "Flodesk error hierarchy" do
  describe "hierarchy" do
    it "roots every error class at Flodesk::Error" do
      [
        Flodesk::BadRequestError,
        Flodesk::AuthenticationError,
        Flodesk::NotFoundError,
        Flodesk::RateLimitError,
        Flodesk::ServerError,
        Flodesk::ConnectionError,
        Flodesk::TimeoutError,
        Flodesk::PartialFailureError
      ].each do |klass|
        expect(klass.ancestors).to include(Flodesk::Error)
      end
    end

    it "descends Flodesk::Error from StandardError so a bare rescue catches it" do
      expect(Flodesk::Error.ancestors).to include(StandardError)
    end

    it "makes API errors distinguishable from transport errors" do
      expect(Flodesk::NotFoundError.ancestors).to include(Flodesk::APIError)
      expect(Flodesk::TimeoutError.ancestors).not_to include(Flodesk::APIError)
    end
  end

  describe ".from_response" do
    def build(status:, body: nil, headers: {})
      Flodesk::Error.from_response(status: status, body: body, headers: headers)
    end

    it "maps 400 to BadRequestError" do
      expect(build(status: 400)).to be_a(Flodesk::BadRequestError)
    end

    it "maps 401 to AuthenticationError" do
      expect(build(status: 401)).to be_a(Flodesk::AuthenticationError)
    end

    it "maps 403 to AuthenticationError" do
      expect(build(status: 403)).to be_a(Flodesk::AuthenticationError)
    end

    it "maps 404 to NotFoundError" do
      expect(build(status: 404)).to be_a(Flodesk::NotFoundError)
    end

    it "maps 429 to RateLimitError" do
      expect(build(status: 429)).to be_a(Flodesk::RateLimitError)
    end

    it "maps 500 to ServerError" do
      expect(build(status: 500)).to be_a(Flodesk::ServerError)
    end

    it "maps 503 to ServerError" do
      expect(build(status: 503)).to be_a(Flodesk::ServerError)
    end

    it "maps an undocumented status to a generic Flodesk::Error" do
      error = build(status: 418)

      expect(error).to be_a(Flodesk::Error)
      expect(error).not_to be_a(Flodesk::ServerError)
      expect(error).not_to be_a(Flodesk::BadRequestError)
    end

    it "retains the status on the error" do
      expect(build(status: 404).status).to eq(404)
    end
  end

  describe "envelope parsing" do
    it "exposes code and message from a well-formed envelope" do
      error = Flodesk::Error.from_response(
        status: 400,
        body: { "code" => "invalid_email", "message" => "Email is invalid" }
      )

      expect(error.code).to eq("invalid_email")
      expect(error.message).to eq("Email is invalid")
    end

    it "parses the real unauthorized envelope observed from the live API" do
      error = Flodesk::Error.from_response(
        status: 401,
        body: { "code" => "unauthorized", "message" => "Unauthorized access is denied!" }
      )

      expect(error).to be_a(Flodesk::AuthenticationError)
      expect(error.code).to eq("unauthorized")
      expect(error.message).to eq("Unauthorized access is denied!")
    end

    it "falls back to a status-derived message when the body is empty" do
      error = Flodesk::Error.from_response(status: 404, body: nil)

      expect(error.code).to be_nil
      expect(error.message).to include("404")
      expect(error).to be_a(Flodesk::NotFoundError)
    end

    it "does not raise when the body is HTML from an edge proxy" do
      html = "<html><body>503 Service Unavailable</body></html>"

      error = nil
      expect { error = Flodesk::Error.from_response(status: 503, body: html) }.not_to raise_error

      expect(error).to be_a(Flodesk::ServerError)
      expect(error.raw_body).to eq(html)
      expect(error.code).to be_nil
    end

    it "leaves code and message nil when valid JSON omits both fields" do
      error = Flodesk::Error.from_response(status: 400, body: { "unexpected" => "shape" })

      expect(error.code).to be_nil
      expect(error.message).to include("400")
      expect(error.raw_body).to eq({ "unexpected" => "shape" })
    end

    it "retains the raw body for debugging" do
      body = { "code" => "x", "message" => "y" }

      expect(Flodesk::Error.from_response(status: 400, body: body).raw_body).to eq(body)
    end
  end

  describe Flodesk::RateLimitError do
    it "exposes the observed rate limit headers" do
      error = Flodesk::Error.from_response(
        status: 429,
        body: { "code" => "rate_limited", "message" => "Too many requests" },
        headers: { "x-fd-ratelimit-limit" => "100", "x-fd-ratelimit-remaining" => "0" }
      )

      expect(error.rate_limit).to eq(100)
      expect(error.rate_limit_remaining).to eq(0)
    end

    it "reports nil for rate limit values when the headers are absent" do
      error = Flodesk::Error.from_response(status: 429, body: nil, headers: {})

      expect(error.rate_limit).to be_nil
      expect(error.rate_limit_remaining).to be_nil
    end

    it "documents that the API provides no reset time" do
      error = Flodesk::Error.from_response(status: 429, body: nil)

      expect(error.retry_after).to be_nil
    end
  end

  describe Flodesk::PartialFailureError do
    it "is rescuable as Flodesk::Error" do
      expect(Flodesk::PartialFailureError.ancestors).to include(Flodesk::Error)
    end

    it "carries the batch result so successes survive the raise" do
      # A plain double, not a verifying one: this asserts only that the error
      # passes through whatever result it is handed. BatchResult itself is
      # covered in spec/flodesk/batch_result_spec.rb.
      result = double(failures: [1], successes: [2, 3])
      error = Flodesk::PartialFailureError.new(result: result)

      expect(error.result).to be(result)
    end
  end
end
