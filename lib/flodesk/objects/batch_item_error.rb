# frozen_string_literal: true

module Flodesk
  # A single record's failure within a batch operation.
  #
  # `index` is the zero-based position in the submitted array, which is what
  # makes a failure actionable: it identifies which of your inputs was rejected
  # even when neither `id` nor `email` came back.
  BatchItemError = Data.define(:index, :email, :id, :code, :message, :raw) do
    def self.from(payload)
      return nil if payload.nil?

      new(
        index: payload["index"],
        email: payload["email"],
        id: payload["id"],
        code: payload["code"],
        message: payload["message"],
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
