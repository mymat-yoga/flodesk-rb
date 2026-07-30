# frozen_string_literal: true

module Flodesk
  module Resources
    # Operations under the `Segment` tag of the Flodesk API.
    class Segments < Base
      PATH = "/segments"

      # GET /segments
      def list(page: nil, per_page: nil)
        paginated_list(PATH, klass: Segment, page: page, per_page: per_page)
      end

      # Walks every segment across all pages, fetching each page on demand.
      def auto_paging_each(page: nil, per_page: nil, &)
        each_page_item(PATH, klass: Segment, page: page, per_page: per_page, &)
      end

      # GET /segments/{id}
      def retrieve(id)
        Segment.from(get("#{PATH}/#{encode_segment(id)}"))
      end

      # POST /segments — returns 201 with the created segment.
      #
      # NOT idempotent. This endpoint creates a new record and the API offers no
      # idempotency key, so a retry after a timeout or 5xx would leave a second,
      # duplicate segment behind. Failures are surfaced to the caller instead.
      def create(name:, color: nil)
        raise ArgumentError, "name is required" if name.nil? || name.to_s.empty?

        Segment.from(
          post(
            PATH,
            body: { "name" => name.to_s, "color" => color }.compact,
            idempotent: false
          )
        )
      end

      # GET /segments/colors — the palette available for segment colors.
      #
      # The only error this endpoint documents is 401.
      def colors
        get("#{PATH}/colors")
      end
    end
  end
end
