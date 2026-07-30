# frozen_string_literal: true

# Contract verification against the vendored API description.
#
# The OpenAPI file is used as an *oracle*, not as generator input. Client code
# stays hand-written and idiomatic, while these examples detect drift: dropping in
# a newer `openapi.json` fails the build when Flodesk documents an operation the
# client does not implement.

# Constants live in a named module rather than inside the example groups.
# A constant assigned inside a block binds to the enclosing lexical scope — at
# the top of a spec file that means Object — so defining them in blocks would
# leak `OPERATION_MAP` and friends globally across the suite.
module ContractFixtures
  SPEC_PATH = File.expand_path("../fixtures/openapi.json", __dir__)

  # Every documented operation, mapped to the client method that implements it.
  #
  # Adding an entry here is how a newly documented endpoint gets wired up; the
  # completeness example below fails until every operationId is present.
  OPERATION_MAP = {
    "listSubscribers" => %i[subscribers list],
    "createOrUpdateSubscriber" => %i[subscribers upsert],
    "batchCreateOrUpdateSubscribers" => %i[subscribers batch_upsert],
    "retrieveSubscriber" => %i[subscribers retrieve],
    "addSubscriberToSegments" => %i[subscribers add_to_segments],
    "removeSubscriberFromSegments" => %i[subscribers remove_from_segments],
    "unsubscribeSubscriber" => %i[subscribers unsubscribe],
    "listSegments" => %i[segments list],
    "createSegment" => %i[segments create],
    "retrieveSegment" => %i[segments retrieve],
    "listColors" => %i[segments colors],
    "listCustomFields" => %i[custom_fields list],
    "listAllCustomFields" => %i[custom_fields list_all],
    "createCustomField" => %i[custom_fields create],
    "listWorkflows" => %i[workflows list],
    "addSubscriberToWorkflow" => %i[workflows add_subscriber],
    "removeSubscriberFromWorkflow" => %i[workflows remove_subscriber],
    "listWebhooks" => %i[webhooks list],
    "createWebhook" => %i[webhooks create],
    "retrieveWebhook" => %i[webhooks retrieve],
    "updateWebhook" => %i[webhooks update],
    "deleteWebhook" => %i[webhooks delete],
    "listCampaigns" => %i[campaigns list],
    "publishCanvaEmail" => %i[campaigns publish_canva],
    "getCanvaDesignState" => %i[campaigns canva_design_state]
  }.freeze

  # Parameter names the client deliberately translates from an idiomatic
  # snake_case argument. The value is the caller-facing keyword.
  TRANSLATED_PARAMS = {
    "perPage" => :per_page,
    "Search" => :search,
    "OrderBy" => :order_by,
    "Sort" => :sort,
    "Status" => :status,
    "SharedAsTemplate" => :shared_as_template
  }.freeze

  # Response schema -> the value object that models it.
  SCHEMA_MAP = {
    "SubscriberRes" => Flodesk::Subscriber,
    "SegmentRes" => Flodesk::Segment,
    "CustomFieldRes" => Flodesk::CustomField,
    "WorkflowRes" => Flodesk::Workflow,
    "WebhookRes" => Flodesk::Webhook,
    "CampaignItem" => Flodesk::Campaign,
    "BatchItemError" => Flodesk::BatchItemError,
    "PaginationRes" => Flodesk::Page
  }.freeze
end

RSpec.describe "OpenAPI contract" do
  let(:api) { JSON.parse(File.read(ContractFixtures::SPEC_PATH)) }
  let(:schemas) { api.dig("components", "schemas") }
  let(:operation_map) { ContractFixtures::OPERATION_MAP }
  let(:client) { Flodesk::Client.new(api_key: "k") }

  def operations
    api["paths"].flat_map do |path, methods|
      methods.filter_map do |verb, op|
        next unless op.is_a?(Hash) && op["operationId"]

        { id: op["operationId"], verb: verb, path: path, op: op }
      end
    end
  end

  describe "the vendored specification" do
    it "is present and parseable" do
      expect(File).to exist(ContractFixtures::SPEC_PATH)
      expect(api["openapi"]).to start_with("3.")
    end

    it "targets the base URL the client defaults to" do
      expect(api.dig("servers", 0, "url")).to eq(Flodesk::DEFAULT_BASE_URL)
    end

    it "declares the api_key security scheme the client implements" do
      expect(api.dig("components", "securitySchemes", "api_key", "scheme")).to eq("basic")
    end
  end

  describe "operation coverage" do
    it "implements every documented operation" do
      missing = operations.map { |o| o[:id] } - operation_map.keys

      expect(missing).to be_empty,
                         "Undocumented in OPERATION_MAP (newly added upstream?): #{missing.inspect}"
    end

    it "maps no operation that the specification does not document" do
      stale = operation_map.keys - operations.map { |o| o[:id] }

      expect(stale).to be_empty, "Mapped but no longer documented: #{stale.inspect}"
    end

    it "exposes a callable method for every mapped operation" do
      unimplemented = operation_map.filter_map do |id, (resource, method)|
        "#{id} -> #{resource}##{method}" unless client.public_send(resource).respond_to?(method)
      end

      expect(unimplemented).to be_empty
    end

    it "covers all 25 documented operations" do
      expect(operations.size).to eq(25)
      expect(operation_map.size).to eq(25)
    end
  end

  describe "query parameter coverage" do
    it "accepts a keyword for every documented query parameter" do
      unaccepted = operations.flat_map do |o|
        resource, method = operation_map.fetch(o[:id])
        next [] unless client.public_send(resource).respond_to?(method)

        # Method#parameters returns an Array of [type, name] pairs.
        params = client.public_send(resource).method(method).parameters
        next [] if params.any? { |type, _| type == :keyrest }

        accepted = params.filter_map { |type, name| name if %i[key keyreq].include?(type) }

        (o[:op]["parameters"] || [])
          .select { |p| p["in"] == "query" }
          .map { |p| ContractFixtures::TRANSLATED_PARAMS.fetch(p["name"], p["name"].to_sym) }
          .reject { |name| accepted.include?(name) }
          .map { |name| "#{o[:id]} does not accept #{name}" }
      end

      expect(unaccepted).to be_empty
    end

    it "translates the non-standard parameter names rather than passing them through" do
      # These are the API's inconsistencies; callers must never type them.
      expect(Flodesk::Resources::Workflows::PER_PAGE_KEY).to eq("perPage")
      expect(Flodesk::Resources::Campaigns::FILTER_KEYS.values)
        .to contain_exactly("Search", "OrderBy", "Sort", "Status", "SharedAsTemplate")
    end
  end

  describe "value object coverage" do
    it "declares a member for every documented property" do
      gaps = ContractFixtures::SCHEMA_MAP.flat_map do |schema_name, klass|
        documented = schemas.fetch(schema_name)["properties"].keys.map(&:to_sym)
        (documented - klass.members).map { |m| "#{klass}##{m} missing (#{schema_name})" }
      end

      expect(gaps).to be_empty
    end

    it "models SegmentMini with the same object as SegmentRes" do
      # The API nests a narrower segment shape inside subscriber payloads.
      mini = schemas.fetch("SegmentMini")["properties"].keys.map(&:to_sym)

      expect(mini - Flodesk::Segment.members).to be_empty
    end

    it "keeps every value object's raw payload reachable" do
      ContractFixtures::SCHEMA_MAP.each_value do |klass|
        expect(klass.members).to include(:raw), "#{klass} has no raw escape hatch"
      end
    end
  end

  describe "enum coverage" do
    it "matches the documented subscriber status enum" do
      documented = schemas.dig("SubscriberRes", "properties", "status", "enum")

      expect(Flodesk::Enums::SUBSCRIBER_STATUSES).to eq(documented)
    end

    it "matches the documented subscriber source enum" do
      documented = schemas.dig("SubscriberRes", "properties", "source", "enum")

      expect(Flodesk::Enums::SUBSCRIBER_SOURCES).to eq(documented)
    end

    it "matches the documented campaign status enum" do
      documented = schemas.dig("CampaignItem", "properties", "status", "enum")

      expect(Flodesk::Enums::CAMPAIGN_STATUSES).to eq(documented)
    end

    it "matches the documented workflow statuses filter enum" do
      documented = api.dig("paths", "/workflows", "get", "parameters")
                      .find { |p| p["name"] == "statuses" }
                      .dig("schema", "items", "enum")

      expect(Flodesk::Enums::WORKFLOW_STATUSES).to eq(documented)
    end

    it "matches the documented webhook events" do
      # Compared as a set: the declaration order carries no meaning.
      expect(Flodesk::Enums::WEBHOOK_EVENTS).to match_array(api["x-webhooks"].keys)
    end
  end

  describe "status code coverage" do
    it "maps every documented error status to a known error class" do
      documented = operations.flat_map { |o| o[:op]["responses"].keys }
                             .map(&:to_i).select { |s| s >= 400 }.uniq.sort

      unmapped = documented.reject do |status|
        Flodesk::Error.from_response(status: status).is_a?(Flodesk::APIError)
      end

      expect(unmapped).to be_empty
      expect(documented).to include(400, 401, 404, 429)
    end

    it "maps each documented status to a distinct, meaningful class" do
      expect(Flodesk::Error.from_response(status: 400)).to be_a(Flodesk::BadRequestError)
      expect(Flodesk::Error.from_response(status: 401)).to be_a(Flodesk::AuthenticationError)
      expect(Flodesk::Error.from_response(status: 404)).to be_a(Flodesk::NotFoundError)
      expect(Flodesk::Error.from_response(status: 429)).to be_a(Flodesk::RateLimitError)
    end

    it "records that the specification defines no error body schema" do
      # The `{code, message}` envelope the client parses was established by
      # probing the live API. If a future spec starts declaring error schemas,
      # this example fails as a prompt to verify the parser against them.
      declared = operations.flat_map do |o|
        o[:op]["responses"].filter_map do |status, response|
          next if status.to_i < 400

          response.dig("content", "application/json", "schema")
        end
      end

      expect(declared).to be_empty
    end
  end

  describe "webhook event coverage" do
    it "parses every documented inbound event" do
      handler = Flodesk::Webhooks::Handler.new(token: "t" * 32)

      api["x-webhooks"].each_key do |event_name|
        payload = {
          "event_name" => event_name,
          "event_time" => "2024-01-01T00:00:00.000Z",
          "webhook_id" => "wh_1",
          "subscriber" => { "id" => "sub_1" }
        }

        event = handler.call(body: JSON.generate(payload), token: "t" * 32)

        expect(event).to be_known
        expect(event.event_name).to eq(event_name)
      end
    end

    it "declares no security scheme for webhooks, which is why verification is mandatory" do
      api["x-webhooks"].each_value do |definition|
        expect(definition["post"]["security"]).to eq([])
      end
    end
  end

  describe "documented limits" do
    it "enforces the documented per_page maximum" do
      expect(Flodesk::Resources::Base::MAX_PER_PAGE).to eq(100)
    end

    it "enforces the documented batch maximum of 50" do
      documented = api.dig("paths", "/subscribers/batch", "post", "requestBody", "content")
                      .values.first
                      .dig("schema", "properties", "subscribers", "description")

      expect(documented).to include("50")
      expect(Flodesk::Resources::Subscribers::MAX_BATCH_SIZE).to eq(50)
    end

    it "enforces the documented segment cap of 50" do
      documented = schemas.dig("SubscriberRes", "properties", "segments", "description")

      expect(documented).to include("50")
      expect(Flodesk::Resources::Subscribers::MAX_SEGMENTS).to eq(50)
    end
  end
end
