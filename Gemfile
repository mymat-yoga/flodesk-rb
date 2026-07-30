# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in flodesk-rb.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.0"

gem "rspec", "~> 3.0"

gem "rubocop", "~> 1.21"

gem "webmock", "~> 3.0"

# Development only. The gem must never depend on Rails or ActiveSupport at
# runtime; this is here so the suite can exercise the optional integration.
gem "activesupport", "~> 8.0"

# Development only, so the install generator can be tested for real rather than
# skipped. The gem never requires railties itself.
gem "railties", "~> 8.0"
