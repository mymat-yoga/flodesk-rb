# frozen_string_literal: true

module Flodesk
  module Resources
    # Operations under the `Subscriber` tag of the Flodesk API.
    class Subscribers < Base
      PATH = "/subscribers"

      # The API caps segments per subscriber at 50.
      MAX_SEGMENTS = 50

      # The API caps a batch at 50 subscribers per request. Combined with the
      # endpoint's 20-requests-per-minute limit, that is a ceiling of 1,000
      # upserts per minute.
      MAX_BATCH_SIZE = 50

      # GET /subscribers
      #
      # Issues exactly one request. Use {#auto_paging_each} to walk every page.
      def list(page: nil, per_page: nil, status: nil, segment_id: nil)
        paginated_list(
          PATH, klass: Subscriber, page: page, per_page: per_page,
                filters: list_filters(status: status, segment_id: segment_id)
        )
      end

      # Walks every subscriber across all pages, fetching each page on demand.
      #
      # Traversing a large list can consume the entire 100-requests-per-minute
      # budget, which is why this is opt-in rather than the behavior of `list`.
      def auto_paging_each(page: nil, per_page: nil, status: nil, segment_id: nil, &)
        each_page_item(
          PATH, klass: Subscriber, page: page, per_page: per_page,
                filters: list_filters(status: status, segment_id: segment_id), &
        )
      end

      # GET /subscribers/{id_or_email}
      #
      # `id_or_email` may be either; an email is percent-encoded into the path.
      def retrieve(id_or_email)
        Subscriber.from(get("#{PATH}/#{encode_segment(id_or_email)}"))
      end

      # POST /subscribers — creates or updates.
      #
      # Declared idempotent: repeating it converges on the same state, so it is
      # safe to retry after a timeout or 5xx.
      #
      # The API returns 200 for both a creation and an update and never reports
      # which occurred, so this cannot tell you whether the subscriber was new.
      def upsert(**attrs)
        Subscriber.from(post(PATH, body: subscriber_payload(attrs), idempotent: true))
      end

      # POST /subscribers/batch — up to 50 records in one request.
      #
      # Returns a {BatchResult}. Because the API reports per-record failures
      # inside a 200 response, this raises {PartialFailureError} when any record
      # failed — carrying the full result, so successes are not lost. Pass
      # `raise_on_failure: false` to receive the result quietly instead.
      def batch_upsert(records, raise_on_failure: true)
        payload = batch_payload(records)
        result = BatchResult.from(
          post("#{PATH}/batch", body: { "subscribers" => payload }, idempotent: true)
        )

        raise PartialFailureError.new(result: result) if raise_on_failure && !result.success?

        result
      end

      # POST /subscribers/{id_or_email}/segments
      #
      # Idempotent: adding a segment the subscriber already has has no further
      # effect.
      def add_to_segments(id_or_email, segment_ids)
        Subscriber.from(
          post(
            "#{PATH}/#{encode_segment(id_or_email)}/segments",
            body: { "segment_ids" => validate_segment_ids!(segment_ids) },
            idempotent: true
          )
        )
      end

      # DELETE /subscribers/{id_or_email}/segments
      #
      # Idempotent: removing a segment the subscriber does not have has no
      # further effect.
      def remove_from_segments(id_or_email, segment_ids)
        Subscriber.from(
          delete(
            "#{PATH}/#{encode_segment(id_or_email)}/segments",
            body: { "segment_ids" => validate_segment_ids!(segment_ids) }
          )
        )
      end

      # POST /subscribers/{id_or_email}/unsubscribe
      #
      # Idempotent: unsubscribing is a terminal state, so repeating it is safe.
      def unsubscribe(id_or_email)
        Subscriber.from(
          post("#{PATH}/#{encode_segment(id_or_email)}/unsubscribe", idempotent: true)
        )
      end

      private

      def list_filters(status:, segment_id:)
        {
          "status" => validate_enum!("status", status, Enums::SUBSCRIBER_STATUSES),
          "segment_id" => segment_id
        }
      end

      # Builds a `CreateOrUpdateSubscriberItem`. `index` is included in the error
      # message when validating a batch, so a rejected record is identifiable.
      def subscriber_payload(attrs, index: nil)
        attrs = normalize_keys(attrs)
        validate_identifier!(attrs, index)

        {
          "id" => attrs[:id],
          "email" => attrs[:email],
          "first_name" => attrs[:first_name],
          "last_name" => attrs[:last_name],
          "custom_fields" => stringify_custom_fields(attrs[:custom_fields]),
          "segment_ids" => attrs[:segment_ids] && validate_segment_ids!(attrs[:segment_ids]),
          "double_optin" => attrs[:double_optin],
          "optin_ip" => attrs[:optin_ip],
          "optin_timestamp" => attrs[:optin_timestamp]
        }.compact
      end

      def batch_payload(records)
        raise ArgumentError, "records cannot be empty" if records.nil? || records.empty?

        if records.size > MAX_BATCH_SIZE
          raise ArgumentError,
                "a batch accepts at most #{MAX_BATCH_SIZE} records, got #{records.size}"
        end

        records.each_with_index.map { |record, i| subscriber_payload(record, index: i) }
      end

      def normalize_keys(attrs)
        return {} if attrs.nil?

        attrs.to_h { |k, v| [k.to_sym, v] }
      end

      def validate_identifier!(attrs, index)
        return if present?(attrs[:id]) || present?(attrs[:email])

        at = index.nil? ? "" : " at index #{index}"
        raise ArgumentError, "either email or id must be provided#{at}"
      end

      def validate_segment_ids!(segment_ids)
        ids = Array(segment_ids)
        raise ArgumentError, "segment_ids cannot be empty" if ids.empty?

        if ids.size > MAX_SEGMENTS
          raise ArgumentError,
                "a subscriber accepts at most #{MAX_SEGMENTS} segments, got #{ids.size}"
        end

        ids.map(&:to_s)
      end

      # Custom field values are typed `string` throughout the API, so anything
      # else would simply be rejected. Coercing is friendlier than raising and
      # cannot lose information. `nil` is preserved: it means "clear this
      # field", which is a different instruction from the empty string.
      def stringify_custom_fields(fields)
        return nil if fields.nil?

        fields.to_h { |key, value| [key.to_s, value&.to_s] }
      end

      def present?(value)
        !value.nil? && !value.to_s.empty?
      end
    end
  end
end
