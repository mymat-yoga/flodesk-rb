# frozen_string_literal: true

module Flodesk
  # A subscriber.
  Subscriber = Data.define(
    :id, :status, :email, :source, :first_name, :last_name,
    :segments, :custom_fields, :optin_ip, :optin_timestamp, :created_at, :raw
  ) do
    def self.from(payload)
      return nil if payload.nil?

      new(
        id: payload["id"],
        status: Coercion.enum(payload["status"], Enums::SUBSCRIBER_STATUSES),
        email: payload["email"],
        source: Coercion.enum(payload["source"], Enums::SUBSCRIBER_SOURCES),
        first_name: payload["first_name"],
        last_name: payload["last_name"],
        segments: Coercion.array_of(Segment, payload["segments"]),
        custom_fields: Coercion.string_hash(payload["custom_fields"]),
        optin_ip: payload["optin_ip"],
        optin_timestamp: Coercion.time(payload["optin_timestamp"]),
        created_at: Coercion.time(payload["created_at"]),
        raw: Coercion.snapshot(payload)
      )
    end

    # The payload exactly as the API sent it, including any field this gem does
    # not declare.
    def to_h
      raw
    end

    # True when this subscriber can receive marketing email.
    def active?
      status == :active
    end
  end
end
