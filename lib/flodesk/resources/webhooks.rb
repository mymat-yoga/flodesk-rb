# frozen_string_literal: true

module Flodesk
  module Resources
    # Operations under the `Webhook` tag of the Flodesk API.
    #
    # Registering a webhook is only half the job. Flodesk signs nothing — the API
    # description declares `security: []` on all three events — so the endpoint
    # you register must be able to establish authenticity by other means. See
    # {Flodesk::Webhooks::Handler} for the two supported strategies, and choose
    # one before deciding what `post_url` to register here.
    class Webhooks < Base
      PATH = "/webhooks"

      # GET /webhooks
      def list(page: nil, per_page: nil)
        paginated_list(PATH, klass: Webhook, page: page, per_page: per_page)
      end

      # Walks every webhook across all pages, fetching each page on demand.
      def auto_paging_each(page: nil, per_page: nil, &)
        each_page_item(PATH, klass: Webhook, page: page, per_page: per_page, &)
      end

      # GET /webhooks/{id}
      def retrieve(id)
        Webhook.from(get("#{PATH}/#{encode_segment(id)}"))
      end

      # POST /webhooks — returns 201 with the created webhook.
      #
      # NOT idempotent: this creates a new registration and the API offers no
      # idempotency key, so a retry could leave a duplicate webhook delivering
      # every event twice.
      def create(name:, post_url:, events:)
        raise ArgumentError, "name is required" if blank?(name)
        raise ArgumentError, "post_url is required" if blank?(post_url)

        Webhook.from(
          post(
            PATH,
            body: {
              "name" => name.to_s,
              "post_url" => post_url.to_s,
              "events" => validate_events!(events)
            },
            idempotent: false
          )
        )
      end

      # PUT /webhooks/{id}
      #
      # Idempotent: PUT replaces the registration's state, so repeating it
      # converges on the same result. Every field is optional; only those
      # supplied are sent.
      def update(id, name: nil, post_url: nil, events: nil)
        body = {
          "name" => name&.to_s,
          "post_url" => post_url&.to_s,
          "events" => events.nil? ? nil : validate_events!(events)
        }.compact

        raise ArgumentError, "at least one of name, post_url or events is required" if body.empty?

        Webhook.from(put("#{PATH}/#{encode_segment(id)}", body: body))
      end

      # DELETE /webhooks/{id} — returns 204.
      #
      # Idempotent. Returns nil, since a 204 carries no body to parse.
      def delete(id)
        super("#{PATH}/#{encode_segment(id)}")
      end

      private

      # Flodesk delivers exactly three events. Rejecting anything else here
      # avoids registering a webhook that can never fire.
      def validate_events!(events)
        list = Array(events).map(&:to_s)
        raise ArgumentError, "events cannot be empty" if list.empty?

        list.each { |event| validate_enum!("events", event, Enums::WEBHOOK_EVENTS) }
        list
      end

      def blank?(value)
        value.nil? || value.to_s.empty?
      end
    end
  end
end
