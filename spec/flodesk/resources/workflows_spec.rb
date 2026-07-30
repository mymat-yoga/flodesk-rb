# frozen_string_literal: true

RSpec.describe Flodesk::Resources::Workflows do
  let(:base) { "https://example.test/v1" }
  let(:client) { Flodesk::Client.new(api_key: "k", base_url: base, backoff_base: 0) }
  let(:workflows) { client.workflows }

  describe "#list" do
    it "issues GET /workflows and returns a page of Workflow objects" do
      stub_request(:get, "#{base}/workflows").to_return(
        status: 200,
        body: { "meta" => { "page" => 1 }, "data" => [{ "id" => "wf_1", "name" => "W" }] }.to_json
      )

      page = workflows.list

      expect(page.items).to all(be_a(Flodesk::Workflow))
    end

    it "sends perPage, not per_page — this endpoint is the API's odd one out" do
      req = stub_request(:get, "#{base}/workflows")
            .with(query: { "perPage" => "25" }).to_return(status: 200, body: { "data" => [] }.to_json)

      workflows.list(per_page: 25)

      expect(req).to have_been_requested
    end

    # The API documents this parameter as comma-separated
    # (`statuses=active,paused`), not as repeated keys.
    it "serializes a statuses array comma-separated" do
      req = stub_request(:get, "#{base}/workflows")
            .with(query: { "statuses" => "active,draft" })
            .to_return(status: 200, body: { "data" => [] }.to_json)

      workflows.list(statuses: %w[active draft])

      expect(req).to have_been_requested
    end

    it "accepts a single status" do
      req = stub_request(:get, "#{base}/workflows")
            .with(query: { "statuses" => "active" })
            .to_return(status: 200, body: { "data" => [] }.to_json)

      workflows.list(statuses: "active")

      expect(req).to have_been_requested
    end

    it "accepts symbols" do
      req = stub_request(:get, "#{base}/workflows")
            .with(query: { "statuses" => "active,paused" })
            .to_return(status: 200, body: { "data" => [] }.to_json)

      workflows.list(statuses: %i[active paused])

      expect(req).to have_been_requested
    end

    it "rejects a status outside the documented enum before any request" do
      expect { workflows.list(statuses: %w[active bogus]) }
        .to raise_error(ArgumentError, /statuses/)

      expect(a_request(:get, "#{base}/workflows")).not_to have_been_made
    end

    it "returns an empty page when there are no workflows" do
      stub_request(:get, "#{base}/workflows")
        .to_return(status: 200, body: { "data" => [] }.to_json)

      expect(workflows.list).to be_empty
    end

    it "raises NotFoundError on a 404, which this list endpoint documents" do
      stub_request(:get, "#{base}/workflows").to_return(status: 404, body: "{}")

      expect { workflows.list }.to raise_error(Flodesk::NotFoundError)
    end
  end

  describe "#add_subscriber" do
    it "issues POST /workflows/{id}/subscribers with an email" do
      req = stub_request(:post, "#{base}/workflows/wf_1/subscribers")
            .with(body: { "email" => "a@b.com" }).to_return(status: 204, body: "")

      workflows.add_subscriber("wf_1", email: "a@b.com")

      expect(req).to have_been_requested
    end

    it "accepts an id instead of an email" do
      req = stub_request(:post, "#{base}/workflows/wf_1/subscribers")
            .with(body: { "id" => "sub_1" }).to_return(status: 204, body: "")

      workflows.add_subscriber("wf_1", id: "sub_1")

      expect(req).to have_been_requested
    end

    it "returns nil without parsing a body, because the endpoint returns 204" do
      stub_request(:post, "#{base}/workflows/wf_1/subscribers").to_return(status: 204, body: "")

      expect(workflows.add_subscriber("wf_1", id: "sub_1")).to be_nil
    end

    it "requires either an id or an email" do
      expect { workflows.add_subscriber("wf_1") }.to raise_error(ArgumentError, /email|id/)
      expect(a_request(:post, "#{base}/workflows/wf_1/subscribers")).not_to have_been_made
    end

    it "raises NotFoundError when the workflow does not exist" do
      stub_request(:post, "#{base}/workflows/nope/subscribers").to_return(status: 404, body: "{}")

      expect { workflows.add_subscriber("nope", id: "sub_1") }
        .to raise_error(Flodesk::NotFoundError)
    end

    it "raises BadRequestError on a 400" do
      stub_request(:post, "#{base}/workflows/wf_1/subscribers").to_return(status: 400, body: "{}")

      expect { workflows.add_subscriber("wf_1", id: "sub_1") }
        .to raise_error(Flodesk::BadRequestError)
    end

    it "is retried on a server error, because enrolling twice has no further effect" do
      req = stub_request(:post, "#{base}/workflows/wf_1/subscribers")
            .to_return({ status: 503, body: "{}" }, { status: 204, body: "" })

      workflows.add_subscriber("wf_1", id: "sub_1")

      expect(req).to have_been_requested.twice
    end
  end

  describe "#remove_subscriber" do
    it "issues DELETE /workflows/{id}/subscribers/{id_or_email}" do
      req = stub_request(:delete, "#{base}/workflows/wf_1/subscribers/sub_1")
            .to_return(status: 204, body: "")

      workflows.remove_subscriber("wf_1", "sub_1")

      expect(req).to have_been_requested
    end

    it "percent-encodes an email identifier" do
      req = stub_request(:delete, "#{base}/workflows/wf_1/subscribers/a%2Bx%40b.com")
            .to_return(status: 204, body: "")

      workflows.remove_subscriber("wf_1", "a+x@b.com")

      expect(req).to have_been_requested
    end

    it "returns nil without parsing a body" do
      stub_request(:delete, "#{base}/workflows/wf_1/subscribers/sub_1")
        .to_return(status: 204, body: "")

      expect(workflows.remove_subscriber("wf_1", "sub_1")).to be_nil
    end

    it "raises NotFoundError when the subscriber is not enrolled" do
      stub_request(:delete, "#{base}/workflows/wf_1/subscribers/sub_9")
        .to_return(status: 404, body: "{}")

      expect { workflows.remove_subscriber("wf_1", "sub_9") }
        .to raise_error(Flodesk::NotFoundError)
    end

    it "is retried on a server error, because deletes are idempotent" do
      req = stub_request(:delete, "#{base}/workflows/wf_1/subscribers/sub_1")
            .to_return({ status: 503, body: "{}" }, { status: 204, body: "" })

      workflows.remove_subscriber("wf_1", "sub_1")

      expect(req).to have_been_requested.twice
    end

    it "rejects a blank workflow id" do
      expect { workflows.remove_subscriber("", "sub_1") }.to raise_error(ArgumentError)
    end
  end
end
