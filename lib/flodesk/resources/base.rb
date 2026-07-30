# frozen_string_literal: true

module Flodesk
  module Resources
    # Shared behavior for resource namespaces.
    #
    # Subclasses stay thin: they translate idiomatic Ruby arguments into the
    # shape each endpoint wants, declare whether the operation is safe to retry,
    # and hand the parsed body to a value object.
    class Base
      # The API rejects `per_page` above 100.
      MAX_PER_PAGE = 100

      # Characters left unescaped in a path segment, per RFC 3986 "unreserved".
      UNRESERVED = /[^A-Za-z0-9\-._~]/n

      def initialize(client)
        @client = client
        freeze
      end

      private

      def get(path, query: nil)
        @client.request(:get, path, query: query, idempotent: true).body
      end

      def post(path, body: nil, query: nil, idempotent: false, retry_rate_limit: true)
        @client.request(
          :post, path,
          body: body, query: query, idempotent: idempotent, retry_rate_limit: retry_rate_limit
        ).body
      end

      def put(path, body: nil)
        # PUT replaces the resource's state, so repeating it is safe.
        @client.request(:put, path, body: body, idempotent: true).body
      end

      def delete(path, body: nil)
        @client.request(:delete, path, body: body, idempotent: true).body
      end

      # Fetches one page and wraps it in a Page.
      #
      # The Page is given a fetcher closing over this call's path, filters and
      # page size, which is what lets `auto_paging_each` walk forward without
      # the caller restating any of it.
      def paginated_list(path, klass:, page: nil, per_page: nil,
                         per_page_key: "per_page", filters: {})
        query = pagination(page: page, per_page: per_page, per_page_key: per_page_key)
                .merge(filters.compact)

        Page.from(
          get(path, query: query),
          klass: klass,
          fetcher: lambda { |next_page|
            paginated_list(
              path, klass: klass, page: next_page, per_page: per_page,
                    per_page_key: per_page_key, filters: filters
            )
          }
        )
      end

      # Walks every page of a list operation, fetching each on demand.
      #
      # Returns a lazy Enumerator when no block is given, so nothing is
      # requested until iteration begins and each traversal re-fetches.
      def each_page_item(path, **, &block)
        return to_enum(:each_page_item, path, **) unless block

        paginated_list(path, **).auto_paging_each(&block)
      end

      # Builds the pagination query for an endpoint, translating the uniform
      # caller-facing arguments into whatever spelling the endpoint expects.
      # Most take `per_page`; GET /workflows takes `perPage`.
      def pagination(page:, per_page:, per_page_key: "per_page")
        validate_per_page!(per_page)

        query = {}
        query["page"] = page unless page.nil?
        query[per_page_key] = per_page unless per_page.nil?
        query
      end

      def validate_per_page!(per_page)
        return if per_page.nil?

        return if per_page.is_a?(Integer) && per_page.between?(1, MAX_PER_PAGE)

        raise ArgumentError,
              "per_page must be an Integer between 1 and #{MAX_PER_PAGE}, got #{per_page.inspect}"
      end

      # Validates a value against a closed enum from the API description.
      # Filters are rejected before a request is made, since the API would only
      # reject them after a round trip.
      def validate_enum!(name, value, allowed)
        return nil if value.nil?

        normalized = value.to_s
        unless allowed.include?(normalized)
          raise ArgumentError,
                "#{name} must be one of #{allowed.join(", ")}, got #{value.inspect}"
        end

        normalized
      end

      # Path segments may be an id or an email address, and several endpoints
      # accept either. Emails need percent-encoding so "+" survives the round
      # trip rather than being read as a space.
      def encode_segment(value)
        raise ArgumentError, "identifier cannot be blank" if value.nil? || value.to_s.empty?

        value.to_s.b.gsub(UNRESERVED) { |c| format("%%%02X", c.ord) }
      end
    end
  end
end
