# frozen_string_literal: true

module Flodesk
  # Entry point to the Flodesk API.
  #
  #   client = Flodesk::Client.new(
  #     api_key:  ENV.fetch("FLODESK_API_KEY"),
  #     app_name: "MyApp (myapp.com)"
  #   )
  #   client.subscribers.upsert(email: "a@b.com")
  #
  # There is deliberately no global configuration: per-tenant API keys stay
  # trivial, and no process-wide state can leak between tests. Instances are
  # frozen at construction, so a client assigned to a constant is safe to share
  # across request threads.
  class Client
    DEFAULT_OPEN_TIMEOUT = 5
    DEFAULT_READ_TIMEOUT = 15
    DEFAULT_MAX_RETRIES = 2
    DEFAULT_BACKOFF_BASE = 0.5

    attr_reader :api_key, :app_name, :base_url, :open_timeout, :read_timeout,
                :max_retries, :backoff_base, :auth,
                :subscribers, :segments, :custom_fields, :workflows, :webhooks, :campaigns

    def initialize(api_key: nil, app_name: nil, base_url: DEFAULT_BASE_URL,
                   open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT,
                   max_retries: DEFAULT_MAX_RETRIES, backoff_base: DEFAULT_BACKOFF_BASE)
      # Validate at construction rather than on first request, so a
      # misconfigured initializer fails at boot instead of in a background job.
      raise ArgumentError, "api_key is required" if api_key.nil? || api_key.to_s.strip.empty?
      raise ArgumentError, "max_retries must be >= 0" if max_retries.negative?

      @api_key = api_key.to_s.dup.freeze
      @app_name = app_name.nil? ? nil : app_name.to_s.dup.freeze
      @base_url = base_url.to_s.sub(%r{/+\z}, "").dup.freeze
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @max_retries = max_retries
      @backoff_base = backoff_base
      @auth = Auth::ApiKey.new(@api_key)
      @connection = Connection.new(self)

      build_resources
      freeze
    end

    # Flodesk's documentation asks integrations to identify themselves.
    def user_agent
      [@app_name, "flodesk/#{VERSION}"].compact.join(" ")
    end

    # Rate-limit state from this thread's most recent request, or nil.
    # Only `remaining` is actionable: the API sends no reset header.
    def rate_limit
      RateLimit.last(self)
    end

    # @api private
    def request(...)
      @connection.request(...)
    end

    # Never leak the API key through inspect, which Rails prints in consoles and
    # error pages.
    def inspect
      "#<#{self.class.name} base_url=#{@base_url.inspect} api_key=[REDACTED]>"
    end
    alias to_s inspect

    private

    # Built eagerly rather than memoized lazily: these are tiny, and a frozen
    # client shared across threads must not mutate a memo hash concurrently.
    def build_resources
      @subscribers = Resources::Subscribers.new(self)
      @segments = Resources::Segments.new(self)
      @custom_fields = Resources::CustomFields.new(self)
      @workflows = Resources::Workflows.new(self)
      @webhooks = Resources::Webhooks.new(self)
      @campaigns = Resources::Campaigns.new(self)
    end
  end
end
