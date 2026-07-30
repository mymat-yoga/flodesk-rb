# frozen_string_literal: true

module Flodesk
  # A workflow.
  #
  # The API description declares only `id` and `name`. The list endpoint accepts
  # a `statuses` filter, but the response schema exposes no status field, so any
  # status the API happens to return is reachable through {#to_h}.
  Workflow = Data.define(:id, :name, :raw) do
    def self.from(payload)
      return nil if payload.nil?

      new(id: payload["id"], name: payload["name"], raw: Coercion.snapshot(payload))
    end

    # The payload exactly as the API sent it, including any field this gem does
    # not declare.
    def to_h
      raw
    end
  end
end
