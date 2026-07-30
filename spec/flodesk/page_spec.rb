# frozen_string_literal: true

RSpec.describe Flodesk::Page do
  def build(meta: nil, data: [], klass: Flodesk::Subscriber, fetcher: nil)
    payload = {}
    payload["meta"] = meta if meta
    payload["data"] = data
    described_class.from(payload, klass: klass, fetcher: fetcher)
  end

  let(:meta) { { "page" => 2, "total_pages" => 5, "per_page" => 20, "total_items" => 97 } }

  describe "metadata" do
    it "exposes all four pagination values as integers" do
      page = build(meta: meta)

      expect(page.page).to eq(2)
      expect(page.total_pages).to eq(5)
      expect(page.per_page).to eq(20)
      expect(page.total_items).to eq(97)
    end

    it "reads nil for metadata when meta is absent" do
      page = build(data: [{ "id" => "sub_1" }])

      expect(page.page).to be_nil
      expect(page.total_pages).to be_nil
      expect(page.total_items).to be_nil
    end

    it "still returns items when meta is absent" do
      page = build(data: [{ "id" => "sub_1" }])

      expect(page.items.map(&:id)).to eq(["sub_1"])
    end
  end

  describe "items" do
    it "builds each item into the given value object" do
      page = build(data: [{ "id" => "sub_1" }, { "id" => "sub_2" }])

      expect(page.items).to all(be_a(Flodesk::Subscriber))
      expect(page.items.map(&:id)).to eq(%w[sub_1 sub_2])
    end

    it "is empty when data is an empty array" do
      page = build(meta: meta, data: [])

      expect(page.items).to eq([])
      expect(page).to be_empty
    end

    it "does not raise on an empty result set and still exposes metadata" do
      page = build(meta: meta, data: [])

      expect(page.total_items).to eq(97)
    end

    it "is empty when data is absent entirely" do
      expect(described_class.from({}, klass: Flodesk::Subscriber).items).to eq([])
    end
  end

  describe "Enumerable" do
    subject(:page) { build(meta: meta, data: [{ "id" => "a" }, { "id" => "b" }]) }

    it "is Enumerable" do
      expect(page).to be_a(Enumerable)
    end

    it "iterates its own items without issuing further requests" do
      expect(page.map(&:id)).to eq(%w[a b])
    end

    it "supports Enumerable methods" do
      expect(page.count).to eq(2)
      expect(page.find { |s| s.id == "b" }.id).to eq("b")
    end
  end

  describe "#more_pages?" do
    it "is true when the current page is below the last" do
      expect(build(meta: meta).more_pages?).to be(true)
    end

    it "is false on the final page" do
      final = { "page" => 5, "total_pages" => 5, "per_page" => 20, "total_items" => 97 }

      expect(build(meta: final).more_pages?).to be(false)
    end

    it "is false when metadata is absent, since nothing indicates another page" do
      expect(build(data: [{ "id" => "a" }]).more_pages?).to be(false)
    end
  end

  describe "#to_h" do
    it "returns the raw payload" do
      payload = { "meta" => meta, "data" => [{ "id" => "a" }] }

      page = described_class.from(payload, klass: Flodesk::Subscriber)

      expect(page.to_h).to eq(payload)
    end
  end

  it "is frozen" do
    expect(build(meta: meta)).to be_frozen
  end
end
