# frozen_string_literal: true

module Flodesk
  module Resources
    # Operations under the `Custom Field` tag of the Flodesk API.
    #
    # Custom fields are identified by `key`, which the API derives from the
    # `label` given at creation. Values stored against a field are always
    # strings; see {Subscribers#upsert} for how non-string values are handled.
    class CustomFields < Base
      PATH = "/custom-fields"

      # GET /custom-fields — paginated.
      #
      # Distinct from {#list_all}, which returns every field in one unpaginated
      # response. The two endpoints are easy to confuse.
      def list(page: nil, per_page: nil)
        paginated_list(PATH, klass: CustomField, page: page, per_page: per_page)
      end

      # Walks every custom field across all pages, fetching each on demand.
      def auto_paging_each(page: nil, per_page: nil, &)
        each_page_item(PATH, klass: CustomField, page: page, per_page: per_page, &)
      end

      # GET /custom-fields/all — every field in one response.
      #
      # Returns a plain Array rather than a {Page}, because this endpoint is not
      # paginated and has no `meta` block to report.
      def list_all
        body = get("#{PATH}/all")

        Coercion.array_of(CustomField, body.is_a?(Hash) ? body["data"] : body)
      end

      # POST /custom-fields — returns 201 with the created field.
      #
      # NOT idempotent: this creates a new record and the API offers no
      # idempotency key, so a retry could leave a duplicate field behind.
      def create(label:)
        raise ArgumentError, "label is required" if label.nil? || label.to_s.empty?

        CustomField.from(post(PATH, body: { "label" => label.to_s }, idempotent: false))
      end
    end
  end
end
