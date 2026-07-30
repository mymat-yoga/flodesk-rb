# frozen_string_literal: true

module Flodesk
  # An email campaign.
  Campaign = Data.define(:id, :name, :subject, :status, :created_at, :updated_at, :raw) do
    def self.from(payload)
      return nil if payload.nil?

      new(
        id: payload["id"],
        name: payload["name"],
        subject: payload["subject"],
        # Coerced to a symbol like the subscriber enums, despite the list
        # endpoint spelling its filter parameter `Status`.
        status: Coercion.enum(payload["status"], Enums::CAMPAIGN_STATUSES),
        created_at: Coercion.time(payload["created_at"]),
        updated_at: Coercion.time(payload["updated_at"]),
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
