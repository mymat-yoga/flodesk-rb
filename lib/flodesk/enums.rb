# frozen_string_literal: true

module Flodesk
  # Closed enumerations documented by the API description.
  #
  # These live in one namespace rather than on the individual value objects for
  # two reasons. Constants assigned inside a `Data.define do ... end` block bind
  # to the *enclosing lexical scope*, not to the resulting class — so a
  # `STATUSES` written inside two such blocks silently defines and then clobbers
  # a single `Flodesk::STATUSES`. Collecting them here also gives the contract
  # spec one place to verify against `openapi.json`.
  module Enums
    # `SubscriberRes.status`. The last three are terminal delivery states rather
    # than subscriber actions.
    SUBSCRIBER_STATUSES = %w[
      active unsubscribed unconfirmed bounced complained cleaned
    ].freeze

    # `SubscriberRes.source`.
    SUBSCRIBER_SOURCES = %w[manual csv form_optin integration checkout].freeze

    # The `statuses` filter on `GET /workflows`. Note that the workflow response
    # schema exposes no status field, so these are only ever sent, never parsed.
    WORKFLOW_STATUSES = %w[active paused draft].freeze

    # `CampaignItem.status`, also accepted as the `Status` list filter.
    CAMPAIGN_STATUSES = %w[
      draft pending scheduled composing sending done failed
    ].freeze

    # The only events Flodesk can deliver to a webhook.
    WEBHOOK_EVENTS = %w[
      subscriber.created
      subscriber.added_to_segment
      subscriber.unsubscribed
    ].freeze
  end
end
