# frozen_string_literal: true

RSpec.describe Flodesk::Resources::Campaigns do
  let(:base) { "https://example.test/v1" }
  let(:client) { Flodesk::Client.new(api_key: "k", base_url: base, backoff_base: 0) }
  let(:campaigns) { client.campaigns }

  describe "#list" do
    it "issues GET /campaigns and returns a page of Campaign objects" do
      stub_request(:get, "#{base}/campaigns").to_return(
        status: 200,
        body: { "meta" => { "page" => 1 }, "data" => [{ "id" => "c_1" }] }.to_json
      )

      expect(campaigns.list.items).to all(be_a(Flodesk::Campaign))
    end

    # The filters on this endpoint are PascalCase — unlike anything else in the
    # API — while its pagination parameters remain snake_case.
    it "sends Search in PascalCase, not search" do
      req = stub_request(:get, "#{base}/campaigns")
            .with(query: { "Search" => "spring sale" })
            .to_return(status: 200, body: { "data" => [] }.to_json)

      campaigns.list(search: "spring sale")

      expect(req).to have_been_requested
    end

    it "sends Status in PascalCase" do
      req = stub_request(:get, "#{base}/campaigns")
            .with(query: { "Status" => "draft" }).to_return(status: 200, body: { "data" => [] }.to_json)

      campaigns.list(status: :draft)

      expect(req).to have_been_requested
    end

    it "sends OrderBy and Sort in PascalCase" do
      req = stub_request(:get, "#{base}/campaigns")
            .with(query: { "OrderBy" => "created_at", "Sort" => "desc" })
            .to_return(status: 200, body: { "data" => [] }.to_json)

      campaigns.list(order_by: "created_at", sort: "desc")

      expect(req).to have_been_requested
    end

    it "sends SharedAsTemplate in PascalCase" do
      req = stub_request(:get, "#{base}/campaigns")
            .with(query: { "SharedAsTemplate" => "true" })
            .to_return(status: 200, body: { "data" => [] }.to_json)

      campaigns.list(shared_as_template: true)

      expect(req).to have_been_requested
    end

    it "keeps pagination snake_case despite the PascalCase filters" do
      req = stub_request(:get, "#{base}/campaigns")
            .with(query: { "page" => "2", "per_page" => "50", "Search" => "x" })
            .to_return(status: 200, body: { "data" => [] }.to_json)

      campaigns.list(page: 2, per_page: 50, search: "x")

      expect(req).to have_been_requested
    end

    it "never sends the snake_case spelling of a filter" do
      stub_request(:get, "#{base}/campaigns")
        .with(query: hash_including("Search" => "x"))
        .to_return(status: 200, body: { "data" => [] }.to_json)

      campaigns.list(search: "x")

      expect(a_request(:get, "#{base}/campaigns").with(query: hash_including("search" => "x")))
        .not_to have_been_made
    end

    it "rejects a status outside the documented enum before any request" do
      expect { campaigns.list(status: :archived) }.to raise_error(ArgumentError, /status/)
      expect(a_request(:get, "#{base}/campaigns")).not_to have_been_made
    end

    it "accepts every documented campaign status" do
      Flodesk::Enums::CAMPAIGN_STATUSES.each do |status|
        stub_request(:get, "#{base}/campaigns")
          .with(query: { "Status" => status }).to_return(status: 200, body: { "data" => [] }.to_json)

        expect { campaigns.list(status: status) }.not_to raise_error
      end
    end

    it "raises BadRequestError on a 400" do
      stub_request(:get, "#{base}/campaigns").to_return(status: 400, body: "{}")

      expect { campaigns.list }.to raise_error(Flodesk::BadRequestError)
    end
  end

  describe "#publish_canva" do
    let(:publish_args) do
      {
        bundle_url: "https://canva.test/bundle",
        title: "Spring",
        design_token: "tok",
        page_id: "p1",
        campaign_id: "c_1"
      }
    end

    it "issues POST /campaigns/canva and returns the campaign from a 201" do
      req = stub_request(:post, "#{base}/campaigns/canva")
            .with(
              body: {
                "bundle_url" => "https://canva.test/bundle", "title" => "Spring",
                "design_token" => "tok", "page_id" => "p1", "campaign_id" => "c_1"
              }
            ).to_return(status: 201, body: { "id" => "c_1", "url" => "https://f.test/c" }.to_json)

      result = campaigns.publish_canva(**publish_args)

      expect(result["id"]).to eq("c_1")
      expect(req).to have_been_requested
    end

    # These four examples are the most important in the suite. Publishing sends
    # an email campaign to the entire subscriber list; a retry could send it
    # twice, which is unrecoverable and customer-visible.
    it "is NEVER retried on a server error" do
      req = stub_request(:post, "#{base}/campaigns/canva").to_return(status: 503, body: "{}")

      expect { campaigns.publish_canva(**publish_args) }.to raise_error(Flodesk::ServerError)
      expect(req).to have_been_requested.once
    end

    it "is NEVER retried after a timeout, since the campaign may already be sent" do
      req = stub_request(:post, "#{base}/campaigns/canva").to_timeout

      expect { campaigns.publish_canva(**publish_args) }.to raise_error(Flodesk::TimeoutError)
      expect(req).to have_been_requested.once
    end

    it "is NEVER retried on a connection reset" do
      req = stub_request(:post, "#{base}/campaigns/canva").to_raise(Errno::ECONNRESET)

      expect { campaigns.publish_canva(**publish_args) }.to raise_error(Flodesk::ConnectionError)
      expect(req).to have_been_requested.once
    end

    it "is NEVER retried on a 429, because a 429 cannot prove non-acceptance" do
      req = stub_request(:post, "#{base}/campaigns/canva").to_return(status: 429, body: "{}")

      expect { campaigns.publish_canva(**publish_args) }.to raise_error(Flodesk::RateLimitError)
      expect(req).to have_been_requested.once
    end

    it "raises BadRequestError on a 400" do
      stub_request(:post, "#{base}/campaigns/canva").to_return(status: 400, body: "{}")

      expect { campaigns.publish_canva(**publish_args) }.to raise_error(Flodesk::BadRequestError)
    end

    it "omits fields the caller did not supply" do
      req = stub_request(:post, "#{base}/campaigns/canva")
            .with(body: { "title" => "Spring" })
            .to_return(status: 201, body: { "id" => "c_1" }.to_json)

      campaigns.publish_canva(title: "Spring")

      expect(req).to have_been_requested
    end
  end

  describe "#canva_design_state" do
    it "issues GET /campaigns/canva/design-state" do
      req = stub_request(:get, "#{base}/campaigns/canva/design-state").to_return(
        status: 200, body: { "design_id" => "d1", "campaign_id" => "c_1" }.to_json
      )

      state = campaigns.canva_design_state

      expect(state["design_id"]).to eq("d1")
      expect(req).to have_been_requested
    end

    it "raises NotFoundError when no design state exists" do
      stub_request(:get, "#{base}/campaigns/canva/design-state").to_return(status: 404, body: "{}")

      expect { campaigns.canva_design_state }.to raise_error(Flodesk::NotFoundError)
    end
  end
end
