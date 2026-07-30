# frozen_string_literal: true

RSpec.describe "Flodesk value objects" do
  # A realistic subscriber payload, shaped exactly as the API description
  # declares it.
  let(:subscriber_payload) do
    {
      "id" => "sub_1",
      "status" => "active",
      "email" => "a@b.com",
      "source" => "form_optin",
      "first_name" => "Ada",
      "last_name" => "Lovelace",
      "segments" => [{ "id" => "seg_1", "name" => "Friends" }],
      "custom_fields" => { "favorite_color" => "Lavender" },
      "optin_ip" => "203.0.113.5",
      "optin_timestamp" => "2023-01-02T15:04:05.999Z",
      "created_at" => "2023-01-01T00:00:00.000Z"
    }
  end

  describe Flodesk::Subscriber do
    subject(:subscriber) { described_class.from(subscriber_payload) }

    it "exposes declared attributes as methods" do
      expect(subscriber.id).to eq("sub_1")
      expect(subscriber.email).to eq("a@b.com")
      expect(subscriber.first_name).to eq("Ada")
      expect(subscriber.last_name).to eq("Lovelace")
    end

    it "raises NoMethodError on a misspelled attribute" do
      expect { subscriber.emial }.to raise_error(NoMethodError)
    end

    it "is frozen" do
      expect(subscriber).to be_frozen
    end

    it "compares equal to another object built from the same payload" do
      expect(subscriber).to eq(described_class.from(subscriber_payload))
    end

    describe "raw payload escape hatch" do
      it "round-trips the payload exactly" do
        expect(subscriber.to_h).to eq(subscriber_payload)
      end

      it "preserves a field the gem does not declare" do
        payload = subscriber_payload.merge("loyalty_tier" => "gold")

        object = described_class.from(payload)

        expect(object.to_h["loyalty_tier"]).to eq("gold")
      end

      it "does not raise on an undeclared field" do
        expect { described_class.from(subscriber_payload.merge("brand_new" => 1)) }
          .not_to raise_error
      end

      it "reads nil for a declared field the response omits" do
        object = described_class.from({ "id" => "sub_1" })

        expect(object.email).to be_nil
        expect(object.first_name).to be_nil
      end
    end

    describe "enum coercion" do
      it "coerces a known status to a symbol" do
        expect(subscriber.status).to eq(:active)
      end

      it "coerces every documented status" do
        %w[active unsubscribed unconfirmed bounced complained cleaned].each do |value|
          object = described_class.from({ "status" => value })

          expect(object.status).to eq(value.to_sym)
        end
      end

      it "coerces a known source to a symbol" do
        expect(subscriber.source).to eq(:form_optin)
      end

      it "coerces every documented source" do
        %w[manual csv form_optin integration checkout].each do |value|
          expect(described_class.from({ "source" => value }).source).to eq(value.to_sym)
        end
      end

      it "passes an unknown status through instead of raising" do
        object = nil
        expect { object = described_class.from({ "status" => "hibernating" }) }
          .not_to raise_error

        expect(object.status).to eq("hibernating")
        expect(object.to_h["status"]).to eq("hibernating")
      end

      it "reads nil when the enum field is absent" do
        expect(described_class.from({ "id" => "x" }).status).to be_nil
      end
    end

    describe "timestamp coercion" do
      it "parses a valid ISO 8601 timestamp to a Time" do
        expect(subscriber.created_at).to be_a(Time)
        expect(subscriber.created_at.year).to eq(2023)
      end

      it "parses optin_timestamp" do
        expect(subscriber.optin_timestamp).to be_a(Time)
      end

      it "reads nil when a timestamp is absent" do
        expect(described_class.from({ "id" => "x" }).created_at).to be_nil
      end

      it "passes an unparseable timestamp through instead of raising" do
        object = nil
        expect { object = described_class.from({ "created_at" => "not a date" }) }
          .not_to raise_error

        expect(object.created_at).to eq("not a date")
      end
    end

    describe "nested construction" do
      it "builds segments into Segment objects" do
        expect(subscriber.segments).to all(be_a(Flodesk::Segment))
        expect(subscriber.segments.first.name).to eq("Friends")
      end

      it "returns an empty array when segments are absent" do
        expect(described_class.from({ "id" => "x" }).segments).to eq([])
      end

      it "returns an empty array when segments are an empty list" do
        expect(described_class.from({ "segments" => [] }).segments).to eq([])
      end

      it "exposes custom fields as a string-keyed hash" do
        expect(subscriber.custom_fields).to eq({ "favorite_color" => "Lavender" })
      end

      it "returns an empty hash when custom fields are absent" do
        expect(described_class.from({ "id" => "x" }).custom_fields).to eq({})
      end
    end
  end

  describe Flodesk::Segment do
    it "exposes its attributes" do
      segment = described_class.from({ "id" => "seg_1", "name" => "VIPs", "color" => "#fff" })

      expect(segment.id).to eq("seg_1")
      expect(segment.name).to eq("VIPs")
    end

    it "keeps the raw payload" do
      payload = { "id" => "seg_1", "name" => "VIPs", "subscriber_count" => 12 }

      expect(described_class.from(payload).to_h).to eq(payload)
    end
  end

  describe Flodesk::Webhook do
    it "exposes its attributes and parses created_at" do
      webhook = described_class.from(
        {
          "id" => "wh_1",
          "post_url" => "https://app.test/hooks",
          "events" => ["subscriber.created"],
          "created_at" => "2023-01-01T00:00:00.000Z"
        }
      )

      expect(webhook.id).to eq("wh_1")
      expect(webhook.post_url).to eq("https://app.test/hooks")
      expect(webhook.events).to eq(["subscriber.created"])
      expect(webhook.created_at).to be_a(Time)
    end
  end

  describe Flodesk::CustomField do
    # The schema declares `key` and `label` only — there is no id or name.
    it "exposes its attributes" do
      field = described_class.from({ "key" => "favorite_color", "label" => "Colour" })

      expect(field.key).to eq("favorite_color")
      expect(field.label).to eq("Colour")
    end
  end

  describe Flodesk::Workflow do
    # The schema declares only id and name.
    it "exposes its attributes" do
      workflow = described_class.from({ "id" => "wf_1", "name" => "Welcome" })

      expect(workflow.id).to eq("wf_1")
      expect(workflow.name).to eq("Welcome")
    end

    it "keeps undeclared fields such as status reachable through the raw payload" do
      workflow = described_class.from({ "id" => "wf_1", "status" => "active" })

      expect(workflow.to_h["status"]).to eq("active")
    end
  end

  describe Flodesk::Campaign do
    it "exposes its attributes" do
      campaign = described_class.from(
        {
          "id" => "c_1", "name" => "Spring", "status" => "draft",
          "subject" => "Hello", "created_at" => "2023-01-01T00:00:00.000Z"
        }
      )

      expect(campaign.id).to eq("c_1")
      expect(campaign.name).to eq("Spring")
      expect(campaign.subject).to eq("Hello")
      expect(campaign.created_at).to be_a(Time)
    end

    it "coerces its documented status enum to a symbol" do
      expect(described_class.from({ "status" => "draft" }).status).to eq(:draft)
    end

    it "coerces every documented campaign status" do
      %w[draft pending scheduled composing sending done failed].each do |value|
        expect(described_class.from({ "status" => value }).status).to eq(value.to_sym)
      end
    end

    it "passes an unknown campaign status through instead of raising" do
      expect(described_class.from({ "status" => "archived" }).status).to eq("archived")
    end
  end

  describe "immutability across all value objects" do
    it "freezes every object type" do
      [
        Flodesk::Subscriber.from({ "id" => "1" }),
        Flodesk::Segment.from({ "id" => "1" }),
        Flodesk::CustomField.from({ "key" => "k" }),
        Flodesk::Workflow.from({ "id" => "1" }),
        Flodesk::Webhook.from({ "id" => "1" }),
        Flodesk::Campaign.from({ "id" => "1" })
      ].each { |object| expect(object).to be_frozen }
    end

    it "returns nil from .from when handed nil" do
      expect(Flodesk::Subscriber.from(nil)).to be_nil
    end
  end

  # Regression guard. Constants assigned inside a `Data.define do ... end` block
  # bind to the enclosing lexical scope rather than to the class, so a STATUSES
  # written inside both the Subscriber and Campaign blocks silently defined and
  # then clobbered a single Flodesk::STATUSES — leaving subscriber status
  # coercion checking against the campaign enum. Enums live in Flodesk::Enums
  # precisely to make that impossible.
  describe "enum constant scoping" do
    it "does not leak enum constants onto the Flodesk module" do
      %i[STATUSES SOURCES EVENTS].each do |name|
        expect(Flodesk.const_defined?(name, false)).to be(false),
                                                       "Flodesk::#{name} leaked from a Data.define block"
      end
    end

    it "keeps the subscriber and campaign status enums distinct" do
      expect(Flodesk::Enums::SUBSCRIBER_STATUSES)
        .not_to eq(Flodesk::Enums::CAMPAIGN_STATUSES)
    end

    it "coerces subscriber and campaign statuses independently" do
      expect(Flodesk::Subscriber.from({ "status" => "active" }).status).to eq(:active)
      expect(Flodesk::Campaign.from({ "status" => "draft" }).status).to eq(:draft)

      # A value valid for one must not be treated as valid for the other.
      expect(Flodesk::Subscriber.from({ "status" => "draft" }).status).to eq("draft")
      expect(Flodesk::Campaign.from({ "status" => "active" }).status).to eq("active")
    end
  end
end
