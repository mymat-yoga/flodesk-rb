# frozen_string_literal: true

RSpec.describe "RBS signatures" do
  # A `let`, not a constant: a constant assigned inside a block binds to the
  # enclosing lexical scope, which here means leaking ROOT onto Object.
  let(:root) { File.expand_path("../..", __dir__) }

  # `rbs validate` exits 0 even when it reports errors, so the output has to be
  # inspected rather than the status.
  let(:validation_output) do
    Dir.chdir(root) { `bundle exec rbs -I sig validate 2>&1` }
  end

  it "validates without errors" do
    expect(validation_output).not_to match(/ERROR/)
  end

  it "ships signature files alongside the implementation" do
    expect(Dir[File.join(root, "sig", "**", "*.rbs")]).not_to be_empty
  end

  it "no longer ships the generated Flodesk::Rb stub" do
    expect(File).not_to exist(File.join(root, "sig/flodesk/rb.rbs"))
  end

  describe "coverage of the public surface" do
    let(:signatures) do
      Dir[File.join(root, "sig", "**", "*.rbs")].map { |f| File.read(f) }.join("\n")
    end

    it "declares every value object" do
      %w[
        Subscriber Segment CustomField Workflow Webhook Campaign
        BatchResult BatchItemError Page
      ].each do |name|
        expect(signatures).to match(/class #{name}\b/), "no signature for #{name}"
      end
    end

    it "declares an attr_reader for every member of every value object" do
      objects = {
        "Subscriber" => Flodesk::Subscriber,
        "Segment" => Flodesk::Segment,
        "CustomField" => Flodesk::CustomField,
        "Workflow" => Flodesk::Workflow,
        "Webhook" => Flodesk::Webhook,
        "Campaign" => Flodesk::Campaign,
        "BatchResult" => Flodesk::BatchResult,
        "BatchItemError" => Flodesk::BatchItemError,
        "Page" => Flodesk::Page
      }

      missing = objects.flat_map do |name, klass|
        body = signatures[/class #{name}\b.*?\n  end/m].to_s
        klass.members.reject { |m| body.include?("attr_reader #{m}:") }
                     .map { |m| "#{name}##{m}" }
      end

      expect(missing).to be_empty
    end

    it "declares every error class" do
      %w[
        Error APIError BadRequestError AuthenticationError NotFoundError
        ServerError RateLimitError ConnectionError TimeoutError PartialFailureError
      ].each do |name|
        expect(signatures).to match(/class #{name}\b/), "no signature for #{name}"
      end
    end

    it "declares every resource namespace" do
      %w[Subscribers Segments CustomFields Workflows Webhooks Campaigns].each do |name|
        expect(signatures).to match(/class #{name} < Base/), "no signature for #{name}"
      end
    end

    it "declares every public resource method" do
      client = Flodesk::Client.new(api_key: "k")

      missing = %i[subscribers segments custom_fields workflows webhooks campaigns]
                .flat_map do |resource|
        namespace = client.public_send(resource)
        own = namespace.class.public_instance_methods(false)
        own.reject { |m| signatures.include?("def #{m}:") }
           .map { |m| "#{resource}##{m}" }
      end

      expect(missing).to be_empty
    end

    it "declares the webhook handling surface" do
      expect(signatures).to match(/class Handler\b/)
      expect(signatures).to match(/class Event\b/)
      expect(signatures).to match(/def dedupe_key:/)
      expect(signatures).to match(/def respond:/)
    end
  end
end
