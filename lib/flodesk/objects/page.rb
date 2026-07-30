# frozen_string_literal: true

module Flodesk
  # One page of a list response.
  #
  # Holds the items plus the `meta` block the API returns. A Page never fetches
  # anything by itself: `list` issues exactly one request, and traversing
  # further pages is the explicit opt-in of `auto_paging_each`. Walking a large
  # collection can consume the whole 100-requests-per-minute budget, and that
  # cost should be visible at the call site rather than hidden behind `each`.
  Page = Data.define(
    :items, :page, :per_page, :total_pages, :total_items, :raw, :fetcher
  ) do
    include Enumerable

    # `fetcher` is a callable taking a page number and returning the next Page.
    # It is supplied by the resource that built this Page, and is what
    # `auto_paging_each` walks.
    def self.from(payload, klass:, fetcher: nil)
      payload ||= {}
      meta = payload["meta"] || {}

      new(
        items: Coercion.array_of(klass, payload["data"]),
        page: meta["page"],
        per_page: meta["per_page"],
        total_pages: meta["total_pages"],
        total_items: meta["total_items"],
        raw: Coercion.snapshot(payload),
        fetcher: fetcher
      )
    end

    def each(&)
      items.each(&)
    end

    def empty?
      items.empty?
    end

    # True when the metadata shows a page after this one. False when metadata is
    # absent, since nothing then indicates another page exists.
    def more_pages?
      return false if page.nil? || total_pages.nil?

      page < total_pages
    end

    # The payload exactly as the API sent it.
    def to_h
      raw
    end

    # Walks this page and every page after it, fetching each on demand.
    #
    # Returns a lazy Enumerator, so `.first(5)` fetches only what it needs
    # instead of the whole collection. Deliberately not the behavior of `each`.
    def auto_paging_each(&block)
      return to_enum(:auto_paging_each) unless block_given?

      current = self
      loop do
        current.items.each(&block)
        break unless current.more_pages? && current.fetcher

        current = current.fetcher.call(current.page + 1)
        break if current.nil?
      end
    end
  end
end
