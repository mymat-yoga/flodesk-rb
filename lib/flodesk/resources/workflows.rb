# frozen_string_literal: true

module Flodesk
  module Resources
    # Operations under the `Workflow` tag of the Flodesk API.
    class Workflows < Base
      PATH = "/workflows"

      # This endpoint spells its page-size parameter `perPage`, unlike every
      # other list endpoint in the API, which use `per_page`. Callers pass
      # `per_page:` regardless; the translation happens here.
      PER_PAGE_KEY = "perPage"

      # GET /workflows
      #
      # `statuses` accepts a single value or an array.
      def list(page: nil, per_page: nil, statuses: nil)
        paginated_list(
          PATH, klass: Workflow, page: page, per_page: per_page,
                per_page_key: PER_PAGE_KEY, filters: status_filter(statuses)
        )
      end

      # Walks every workflow across all pages, fetching each page on demand.
      def auto_paging_each(page: nil, per_page: nil, statuses: nil, &)
        each_page_item(
          PATH, klass: Workflow, page: page, per_page: per_page,
                per_page_key: PER_PAGE_KEY, filters: status_filter(statuses), &
        )
      end

      # POST /workflows/{workflow_id}/subscribers — returns 204.
      #
      # Idempotent: enrolling an already-enrolled subscriber has no further
      # effect. Returns nil, since a 204 carries no body to parse.
      def add_subscriber(workflow_id, id: nil, email: nil)
        raise ArgumentError, "either id or email must be provided" if blank?(id) && blank?(email)

        post(
          "#{PATH}/#{encode_segment(workflow_id)}/subscribers",
          body: { "id" => id, "email" => email }.compact,
          idempotent: true
        )
      end

      # DELETE /workflows/{workflow_id}/subscribers/{id_or_email} — returns 204.
      #
      # Idempotent. Returns nil, since a 204 carries no body to parse.
      def remove_subscriber(workflow_id, id_or_email)
        delete(
          "#{PATH}/#{encode_segment(workflow_id)}/subscribers/#{encode_segment(id_or_email)}"
        )
      end

      private

      # `statuses` is an array parameter, but the API documents it as
      # comma-separated (`statuses=active,paused`) rather than repeated keys.
      # A single value is wrapped so callers can pass either form.
      def status_filter(statuses)
        return { "statuses" => nil } if statuses.nil?

        validated = Array(statuses).map do |status|
          validate_enum!("statuses", status, Enums::WORKFLOW_STATUSES)
        end

        { "statuses" => validated.join(",") }
      end

      def blank?(value)
        value.nil? || value.to_s.empty?
      end
    end
  end
end
