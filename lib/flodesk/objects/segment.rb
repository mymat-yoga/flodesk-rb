# frozen_string_literal: true

module Flodesk
  # A segment.
  #
  # Covers both `SegmentRes` and the smaller `SegmentMini` the API nests inside
  # subscriber payloads: fields absent from the narrower shape simply read nil.
  #
  # `segment_type` is `"static"` or `"dynamic"`. It is deliberately not coerced
  # to a Symbol: the specification documents those two values in prose only and
  # declares no enum array, so there is nothing to validate against and
  # inventing a closed set here would be a guess.
  Segment = Data.define(
    :id, :name, :color, :total_active_subscribers, :created_at, :segment_type, :raw
  ) do
    def self.from(payload)
      return nil if payload.nil?

      new(
        id: payload["id"],
        name: payload["name"],
        color: payload["color"],
        total_active_subscribers: payload["total_active_subscribers"],
        created_at: Coercion.time(payload["created_at"]),
        segment_type: payload["segment_type"],
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
