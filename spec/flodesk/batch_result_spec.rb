# frozen_string_literal: true

RSpec.describe Flodesk::BatchResult do
  let(:payload) do
    {
      "successes" => [
        { "id" => "sub_1", "email" => "a@b.com", "status" => "active" },
        { "id" => "sub_2", "email" => "c@d.com", "status" => "active" }
      ],
      "failures" => [
        {
          "index" => 2, "email" => "bad@", "id" => nil,
          "code" => "invalid_email", "message" => "Email is invalid"
        }
      ]
    }
  end

  subject(:result) { described_class.from(payload) }

  it "builds successes into Subscriber objects" do
    expect(result.successes).to all(be_a(Flodesk::Subscriber))
    expect(result.successes.map(&:id)).to eq(%w[sub_1 sub_2])
  end

  it "builds failures into BatchItemError objects" do
    expect(result.failures).to all(be_a(Flodesk::BatchItemError))
  end

  it "exposes every documented failure field, so the failing subset can be retried" do
    failure = result.failures.first

    expect(failure.index).to eq(2)
    expect(failure.email).to eq("bad@")
    expect(failure.id).to be_nil
    expect(failure.code).to eq("invalid_email")
    expect(failure.message).to eq("Email is invalid")
  end

  it "reports failure when any record failed" do
    expect(result.success?).to be(false)
  end

  it "reports success when nothing failed" do
    ok = described_class.from({ "successes" => [{ "id" => "sub_1" }], "failures" => [] })

    expect(ok.success?).to be(true)
  end

  it "reports success when the failures key is absent entirely" do
    expect(described_class.from({ "successes" => [] }).success?).to be(true)
  end

  it "treats a wholly empty payload as successful with nothing done" do
    empty = described_class.from({})

    expect(empty.success?).to be(true)
    expect(empty.successes).to eq([])
    expect(empty.failures).to eq([])
  end

  it "counts records" do
    expect(result.size).to eq(3)
  end

  it "keeps the raw payload" do
    expect(result.to_h).to eq(payload)
  end

  it "is frozen" do
    expect(result).to be_frozen
  end

  describe "#failed_emails" do
    it "returns the emails of failed records, for building a retry batch" do
      expect(result.failed_emails).to eq(["bad@"])
    end

    it "omits failures that carry no email" do
      only_ids = described_class.from(
        { "failures" => [{ "index" => 0, "id" => "sub_9", "code" => "not_found" }] }
      )

      expect(only_ids.failed_emails).to eq([])
    end
  end
end
