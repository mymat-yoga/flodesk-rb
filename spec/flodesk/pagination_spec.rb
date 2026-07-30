# frozen_string_literal: true

# Cross-resource pagination behavior. The point of these examples is that one
# caller-facing interface (`page:` / `per_page:`) covers three different
# upstream spellings: `per_page` on most endpoints, `perPage` on workflows, and
# PascalCase filters on campaigns.
RSpec.describe "Pagination" do
  let(:base) { "https://example.test/v1" }
  let(:client) { Flodesk::Client.new(api_key: "k", base_url: base, backoff_base: 0) }

  def list_body(data: [], page: 1, total_pages: 1, per_page: 20, total_items: nil)
    {
      "meta" => {
        "page" => page, "total_pages" => total_pages,
        "per_page" => per_page, "total_items" => total_items || data.size
      },
      "data" => data
    }.to_json
  end

  describe "uniform interface across differing upstream spellings" do
    it "sends snake_case per_page for subscribers" do
      req = stub_request(:get, "#{base}/subscribers")
            .with(query: { "page" => "2", "per_page" => "50" })
            .to_return(status: 200, body: list_body)

      client.subscribers.list(page: 2, per_page: 50)

      expect(req).to have_been_requested
    end

    it "sends camelCase perPage for workflows from the same arguments" do
      req = stub_request(:get, "#{base}/workflows")
            .with(query: { "page" => "2", "perPage" => "50" })
            .to_return(status: 200, body: list_body)

      client.workflows.list(page: 2, per_page: 50)

      expect(req).to have_been_requested
    end

    it "does not send snake_case per_page to workflows" do
      stub_request(:get, "#{base}/workflows")
        .with(query: hash_including("perPage" => "50"))
        .to_return(status: 200, body: list_body)

      client.workflows.list(per_page: 50)

      expect(a_request(:get, "#{base}/workflows")
        .with(query: hash_including("per_page" => "50"))).not_to have_been_made
    end

    it "sends snake_case per_page for campaigns despite its PascalCase filters" do
      req = stub_request(:get, "#{base}/campaigns")
            .with(query: { "page" => "2", "per_page" => "50" })
            .to_return(status: 200, body: list_body)

      client.campaigns.list(page: 2, per_page: 50)

      expect(req).to have_been_requested
    end

    it "sends snake_case per_page for segments" do
      req = stub_request(:get, "#{base}/segments")
            .with(query: { "page" => "1", "per_page" => "10" })
            .to_return(status: 200, body: list_body)

      client.segments.list(page: 1, per_page: 10)

      expect(req).to have_been_requested
    end

    it "sends snake_case per_page for custom fields" do
      req = stub_request(:get, "#{base}/custom-fields")
            .with(query: { "per_page" => "10" })
            .to_return(status: 200, body: list_body)

      client.custom_fields.list(per_page: 10)

      expect(req).to have_been_requested
    end

    it "sends snake_case per_page for webhooks" do
      req = stub_request(:get, "#{base}/webhooks")
            .with(query: { "per_page" => "10" })
            .to_return(status: 200, body: list_body)

      client.webhooks.list(per_page: 10)

      expect(req).to have_been_requested
    end

    it "sends no pagination parameters when none are given" do
      req = stub_request(:get, "#{base}/subscribers").to_return(status: 200, body: list_body)

      client.subscribers.list

      expect(req).to have_been_requested
    end
  end

  describe "per_page bounds" do
    it "rejects a value above the API cap of 100 without making a request" do
      expect { client.subscribers.list(per_page: 500) }
        .to raise_error(ArgumentError, /per_page/)

      expect(a_request(:get, "#{base}/subscribers")).not_to have_been_made
    end

    it "accepts exactly 100" do
      req = stub_request(:get, "#{base}/subscribers")
            .with(query: { "per_page" => "100" }).to_return(status: 200, body: list_body)

      client.subscribers.list(per_page: 100)

      expect(req).to have_been_requested
    end

    it "rejects zero" do
      expect { client.subscribers.list(per_page: 0) }.to raise_error(ArgumentError, /per_page/)
    end

    it "rejects a negative value" do
      expect { client.subscribers.list(per_page: -5) }.to raise_error(ArgumentError, /per_page/)
    end

    it "rejects a non-integer value" do
      expect { client.subscribers.list(per_page: "50") }.to raise_error(ArgumentError, /per_page/)
    end

    it "enforces the cap on workflows too" do
      expect { client.workflows.list(per_page: 500) }.to raise_error(ArgumentError, /per_page/)
    end
  end

  describe "list issues exactly one request" do
    it "does not auto-page" do
      req = stub_request(:get, "#{base}/subscribers").to_return(
        status: 200,
        body: list_body(data: [{ "id" => "a" }], page: 1, total_pages: 3, total_items: 3)
      )

      page = client.subscribers.list

      expect(page.items.size).to eq(1)
      expect(req).to have_been_requested.once
    end
  end

  describe "auto_paging_each" do
    # The first request carries no `page` parameter, because the caller did not
    # ask for one — the gem does not send parameters it was not given. Page
    # numbers for subsequent requests come from the `meta` block of the
    # preceding response.
    def stub_subscriber_page(number, query:)
      stub_request(:get, "#{base}/subscribers")
        .with(query: query)
        .to_return(
          status: 200,
          body: list_body(
            data: [{ "id" => "sub_#{number}" }],
            page: number, total_pages: 3, total_items: 3
          )
        )
    end

    def stub_three_pages
      stub_subscriber_page(1, query: {})
      stub_subscriber_page(2, query: { "page" => "2" })
      stub_subscriber_page(3, query: { "page" => "3" })
    end

    it "yields every item across all pages in order" do
      stub_three_pages

      ids = client.subscribers.auto_paging_each.map(&:id)

      expect(ids).to eq(%w[sub_1 sub_2 sub_3])
    end

    it "fetches only the first page when only the first item is taken" do
      stub_three_pages

      client.subscribers.auto_paging_each.first(1)

      expect(a_request(:get, "#{base}/subscribers")
        .with(query: hash_including("page" => "2"))).not_to have_been_made
    end

    it "accepts a block" do
      stub_three_pages
      seen = []

      client.subscribers.auto_paging_each { |s| seen << s.id }

      expect(seen).to eq(%w[sub_1 sub_2 sub_3])
    end

    it "uses the endpoint's own per-page parameter name on every page request" do
      stub_request(:get, "#{base}/workflows")
        .with(query: { "perPage" => "100" })
        .to_return(
          status: 200,
          body: list_body(data: [{ "id" => "wf_1" }], page: 1, total_pages: 2)
        )
      stub_request(:get, "#{base}/workflows")
        .with(query: { "page" => "2", "perPage" => "100" })
        .to_return(
          status: 200,
          body: list_body(data: [{ "id" => "wf_2" }], page: 2, total_pages: 2)
        )

      ids = client.workflows.auto_paging_each(per_page: 100).map(&:id)

      expect(ids).to eq(%w[wf_1 wf_2])
    end

    it "propagates an error raised while fetching a later page" do
      stub_request(:get, "#{base}/subscribers")
        .with(query: {})
        .to_return(
          status: 200,
          body: list_body(data: [{ "id" => "a" }], page: 1, total_pages: 2, total_items: 2)
        )
      stub_request(:get, "#{base}/subscribers")
        .with(query: { "page" => "2" })
        .to_return(status: 500, body: "{}")

      expect { client.subscribers.auto_paging_each.to_a }.to raise_error(Flodesk::ServerError)
    end

    it "stops after one page when the metadata reports a single page" do
      stub_request(:get, "#{base}/subscribers").to_return(
        status: 200,
        body: list_body(data: [{ "id" => "only" }], page: 1, total_pages: 1, total_items: 1)
      )

      expect(client.subscribers.auto_paging_each.map(&:id)).to eq(["only"])
    end

    it "yields nothing for an empty collection" do
      stub_request(:get, "#{base}/subscribers").to_return(
        status: 200, body: list_body(data: [], page: 1, total_pages: 0, total_items: 0)
      )

      expect(client.subscribers.auto_paging_each.to_a).to eq([])
    end

    it "can be traversed twice, re-fetching each time" do
      stub_three_pages
      enumerator = client.subscribers.auto_paging_each

      first = enumerator.map(&:id)
      second = enumerator.map(&:id)

      expect(first).to eq(%w[sub_1 sub_2 sub_3])
      expect(second).to eq(first)
    end
  end
end
