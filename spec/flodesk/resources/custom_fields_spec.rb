# frozen_string_literal: true

RSpec.describe Flodesk::Resources::CustomFields do
  let(:base) { "https://example.test/v1" }
  let(:client) { Flodesk::Client.new(api_key: "k", base_url: base, backoff_base: 0) }
  let(:custom_fields) { client.custom_fields }
  let(:field_json) { { "key" => "favorite_color", "label" => "Colour" }.to_json }

  describe "#list" do
    it "issues GET /custom-fields and returns a page of CustomField objects" do
      stub_request(:get, "#{base}/custom-fields").to_return(
        status: 200,
        body: { "meta" => { "page" => 1 }, "data" => [{ "key" => "k", "label" => "L" }] }.to_json
      )

      page = custom_fields.list

      expect(page.items).to all(be_a(Flodesk::CustomField))
      expect(page.items.first.key).to eq("k")
    end

    it "returns an empty page when there are no custom fields" do
      stub_request(:get, "#{base}/custom-fields")
        .to_return(status: 200, body: { "data" => [] }.to_json)

      expect(custom_fields.list).to be_empty
    end
  end

  describe "#list_all" do
    it "issues GET /custom-fields/all" do
      req = stub_request(:get, "#{base}/custom-fields/all").to_return(
        status: 200, body: { "data" => [{ "key" => "k", "label" => "L" }] }.to_json
      )

      custom_fields.list_all

      expect(req).to have_been_requested
    end

    it "returns CustomField objects rather than a Page, since it is not paginated" do
      stub_request(:get, "#{base}/custom-fields/all").to_return(
        status: 200,
        body: { "data" => [{ "key" => "a" }, { "key" => "b" }] }.to_json
      )

      result = custom_fields.list_all

      expect(result).to be_an(Array)
      expect(result.map(&:key)).to eq(%w[a b])
    end

    it "sends no pagination parameters, because the endpoint is not paginated" do
      req = stub_request(:get, "#{base}/custom-fields/all")
            .with(query: {}).to_return(status: 200, body: { "data" => [] }.to_json)

      custom_fields.list_all

      expect(req).to have_been_requested
    end

    it "returns an empty array when there are no custom fields" do
      stub_request(:get, "#{base}/custom-fields/all")
        .to_return(status: 200, body: { "data" => [] }.to_json)

      expect(custom_fields.list_all).to eq([])
    end
  end

  describe "#create" do
    it "issues POST /custom-fields and returns the created field from a 201" do
      req = stub_request(:post, "#{base}/custom-fields")
            .with(body: { "label" => "Colour" }).to_return(status: 201, body: field_json)

      expect(custom_fields.create(label: "Colour").key).to eq("favorite_color")
      expect(req).to have_been_requested
    end

    it "requires a label, which the API marks required" do
      expect { custom_fields.create(label: nil) }.to raise_error(ArgumentError, /label/)
      expect(a_request(:post, "#{base}/custom-fields")).not_to have_been_made
    end

    it "is NOT retried on a server error, to avoid creating a duplicate field" do
      req = stub_request(:post, "#{base}/custom-fields").to_return(status: 503, body: "{}")

      expect { custom_fields.create(label: "Colour") }.to raise_error(Flodesk::ServerError)
      expect(req).to have_been_requested.once
    end

    it "is NOT retried after a timeout" do
      req = stub_request(:post, "#{base}/custom-fields").to_timeout

      expect { custom_fields.create(label: "Colour") }.to raise_error(Flodesk::TimeoutError)
      expect(req).to have_been_requested.once
    end

    it "raises BadRequestError without retrying on a 400" do
      req = stub_request(:post, "#{base}/custom-fields").to_return(status: 400, body: "{}")

      expect { custom_fields.create(label: "Colour") }.to raise_error(Flodesk::BadRequestError)
      expect(req).to have_been_requested.once
    end
  end
end
