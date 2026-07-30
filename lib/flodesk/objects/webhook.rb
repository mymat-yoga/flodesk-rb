# frozen_string_literal: true

module Flodesk
  # A registered webhook.
  Webhook = Data.define(:id, :post_url, :events, :created_at, :raw) do
    def self.from(payload)
      return nil if payload.nil?

      new(
        id: payload["id"],
        post_url: payload["post_url"],
        events: Coercion.snapshot(payload["events"] || []),
        created_at: Coercion.time(payload["created_at"]),
        raw: Coercion.snapshot(payload)
      )
    end

    # The payload exactly as the API sent it, including any field this gem does
    # not declare.
    def to_h
      raw
    end
  end
end
