# frozen_string_literal: true

require_relative "lib/flodesk/version"

Gem::Specification.new do |spec|
  spec.name = "flodesk-rb"
  spec.version = Flodesk::VERSION
  spec.authors = ["Jim"]
  spec.email = ["jim@mymat.yoga"]

  spec.summary = "Ruby client for the Flodesk API"
  spec.description = <<~DESC
    A dependency-free Ruby client for the Flodesk API, built for Rails apps.
    Covers subscribers, segments, custom fields, workflows, webhooks and
    campaigns, and hides the API's rough edges: non-uniform pagination
    parameters, batch responses that report partial failure inside a 200, and
    per-endpoint retry safety.
  DESC
  spec.homepage = "https://github.com/mymat-yoga/flodesk-rb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml
                          openspec/ .claude/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
