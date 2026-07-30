# frozen_string_literal: true

# Ruby client for the Flodesk API (https://developers.flodesk.com).
#
# The gem holds no global mutable configuration: construct a client explicitly
# and pass it around, or assign one to a constant in your application.
#
#   client = Flodesk::Client.new(
#     api_key:  ENV.fetch("FLODESK_API_KEY"),
#     app_name: "MyApp (myapp.com)"
#   )
#
# A single client is safe to share across threads.
module Flodesk
  # The production API root. Every request is issued relative to this.
  DEFAULT_BASE_URL = "https://api.flodesk.com/v1"

  # Ceiling for retry backoff, in seconds.
  #
  # Set to the rate-limit window length. Flodesk returns no rate-limit reset
  # header, so there is no correct wait to compute; this is a documented
  # heuristic and the gem makes no promise of staying within quota.
  MAX_BACKOFF_SECONDS = 60
end

require_relative "flodesk/version"
require_relative "flodesk/errors"
require_relative "flodesk/redaction"
require_relative "flodesk/instrumentation"
require_relative "flodesk/enums"
require_relative "flodesk/coercion"
require_relative "flodesk/objects/segment"
require_relative "flodesk/objects/subscriber"
require_relative "flodesk/objects/custom_field"
require_relative "flodesk/objects/workflow"
require_relative "flodesk/objects/webhook"
require_relative "flodesk/objects/campaign"
require_relative "flodesk/objects/page"
require_relative "flodesk/objects/batch_item_error"
require_relative "flodesk/objects/batch_result"
require_relative "flodesk/response"
require_relative "flodesk/rate_limit"
require_relative "flodesk/auth"
require_relative "flodesk/retry_policy"
require_relative "flodesk/connection"
require_relative "flodesk/resources/base"
require_relative "flodesk/resources/subscribers"
require_relative "flodesk/resources/segments"
require_relative "flodesk/resources/custom_fields"
require_relative "flodesk/resources/workflows"
require_relative "flodesk/resources/webhooks"
require_relative "flodesk/resources/campaigns"
require_relative "flodesk/client"
require_relative "flodesk/webhooks/verification"
require_relative "flodesk/webhooks/event"
require_relative "flodesk/webhooks/handler"

# Self-guarding: loads the Railtie only when Rails is already present.
require_relative "flodesk/rails"
