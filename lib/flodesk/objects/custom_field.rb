# frozen_string_literal: true

module Flodesk
  # A custom field definition.
  #
  # The API identifies custom fields by `key`, not by an id. Values stored
  # against a field are always strings.
  CustomField = Data.define(:key, :label, :raw) do
    def self.from(payload)
      return nil if payload.nil?

      new(key: payload["key"], label: payload["label"], raw: Coercion.snapshot(payload))
    end

    # The payload exactly as the API sent it, including any field this gem does
    # not declare.
    def to_h
      raw
    end
  end
end
