# frozen_string_literal: true

module Flodesk
  # A segment.
  #
  # Covers both `SegmentRes` and the smaller `SegmentMini` the API nests inside
  # subscriber payloads: fields absent from the narrower shape simply read nil.
  Segment = Data.define(
    :id, :name, :color, :total_active_subscribers, :created_at, :raw
  ) do
    def self.from(payload)
      return nil if payload.nil?

      new(
        id: payload["id"],
        name: payload["name"],
        color: payload["color"],
        total_active_subscribers: payload["total_active_subscribers"],
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
