# frozen_string_literal: true

module Flodesk
  module Resources
    # Operations under the `Campaign` tag of the Flodesk API.
    #
    # These endpoints cannot be safely exercised against a live account during
    # development, so they are covered only by specification-derived stubs and
    # are less battle-tested than the subscriber and segment operations.
    class Campaigns < Base
      PATH = "/campaigns"

      # This endpoint's filters are PascalCase, unlike anything else in the API.
      # Its pagination parameters, confusingly, remain snake_case. Callers use
      # idiomatic snake_case throughout and this map does the translating.
      FILTER_KEYS = {
        search: "Search",
        order_by: "OrderBy",
        sort: "Sort",
        status: "Status",
        shared_as_template: "SharedAsTemplate"
      }.freeze

      # GET /campaigns
      def list(page: nil, per_page: nil, **filters)
        paginated_list(
          PATH, klass: Campaign, page: page, per_page: per_page,
                filters: list_filters(**filters)
        )
      end

      # Walks every campaign across all pages, fetching each page on demand.
      def auto_paging_each(page: nil, per_page: nil, **filters, &)
        each_page_item(
          PATH, klass: Campaign, page: page, per_page: per_page,
                filters: list_filters(**filters), &
        )
      end

      # POST /campaigns/canva — publishes an email campaign. Returns 201.
      #
      # ---------------------------------------------------------------------
      # NEVER RETRIED. NOT ON 5xx, NOT ON TIMEOUT, NOT ON 429.
      #
      # This operation sends an email campaign to the subscriber list. A retry
      # can deliver it a second time, which is unrecoverable and visible to
      # every recipient. No response code — including a timeout or a 429 —
      # proves the campaign was not accepted, so the only safe policy is to
      # surface the failure and let a human decide.
      # ---------------------------------------------------------------------
      #
      # Returns the raw response body: the `PublishCanvaRes` schema declares
      # only `id` and `url`, which is not a Campaign.
      def publish_canva(bundle_url: nil, title: nil, design_token: nil,
                        page_id: nil, campaign_id: nil)
        post(
          "#{PATH}/canva",
          body: {
            "bundle_url" => bundle_url,
            "title" => title,
            "design_token" => design_token,
            "page_id" => page_id,
            "campaign_id" => campaign_id
          }.compact,
          idempotent: false,
          retry_rate_limit: false
        )
      end

      # POST /campaigns/studio — publishes an email campaign. Returns 201.
      #
      # ---------------------------------------------------------------------
      # NEVER RETRIED. Same policy as {#publish_canva}, for the same reason.
      #
      # Both endpoints are summarized upstream as publishing a *draft*, which
      # is a weaker hazard than an immediate send. The policy does not lean on
      # that distinction: "draft" is a one-line summary in the specification,
      # not a guarantee, and the failure it would license is unrecoverable and
      # visible to every recipient. Retrying is the bet that cannot be unmade,
      # so it is not taken.
      # ---------------------------------------------------------------------
      #
      # Returns the raw response body: the `PublishStudioRes` schema declares
      # only `id` and `url`, which is not a Campaign.
      def publish_studio(html: nil, title: nil, campaign_id: nil, asset_id: nil)
        post(
          "#{PATH}/studio",
          body: {
            "html" => html,
            "title" => title,
            "campaign_id" => campaign_id,
            "asset_id" => asset_id
          }.compact,
          idempotent: false,
          retry_rate_limit: false
        )
      end

      # GET /campaigns/canva/design-state
      #
      # Returns the raw response body: `CanvaDesignStateRes` declares only
      # `design_id` and `campaign_id`.
      def canva_design_state
        get("#{PATH}/canva/design-state")
      end

      private

      def list_filters(search: nil, order_by: nil, sort: nil, status: nil,
                       shared_as_template: nil)
        {
          FILTER_KEYS[:search] => search,
          FILTER_KEYS[:order_by] => order_by,
          FILTER_KEYS[:sort] => sort,
          FILTER_KEYS[:status] => validate_enum!("status", status, Enums::CAMPAIGN_STATUSES),
          FILTER_KEYS[:shared_as_template] => shared_as_template
        }
      end
    end
  end
end
