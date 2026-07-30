# frozen_string_literal: true

require "rails/generators/base"

module Flodesk
  module Generators
    # Scaffolds `config/initializers/flodesk.rb`.
    #
    # The initializer builds a client and assigns it to a constant in the *host
    # application*, rather than configuring the gem. The gem holds no global
    # mutable state, which keeps per-tenant API keys trivial and leaves nothing
    # process-wide to leak between tests.
    class InstallGenerator < ::Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Creates config/initializers/flodesk.rb wired to Rails credentials."

      class_option :force, type: :boolean, default: false,
                           desc: "Overwrite an existing config/initializers/flodesk.rb"

      INITIALIZER_PATH = "config/initializers/flodesk.rb"

      # Refuses to clobber an existing initializer rather than relying on Thor's
      # collision prompt, which resolves to "overwrite" on a non-interactive
      # shell. This file typically holds hand-tuned client configuration, and
      # re-running the generator should never silently discard it.
      def create_initializer
        if File.exist?(File.join(destination_root, INITIALIZER_PATH)) && !options[:force]
          say_status :skip, "#{INITIALIZER_PATH} already exists (pass --force to replace)", :yellow
          @skipped = true
          return
        end

        template "initializer.rb", INITIALIZER_PATH
      end

      def report_next_steps
        return if @skipped

        say ""
        say "Add your Flodesk API key to credentials:", :green
        say "  bin/rails credentials:edit"
        say "  flodesk_api_key: fd_your_key_here"
        say ""
        say "Create and manage API keys at:", :green
        say "  https://app.flodesk.com/account/integration/api"
        say ""
      end

      private

      # Used by the template to identify the application to Flodesk, which asks
      # integrations to send a descriptive User-Agent.
      def application_name
        ::Rails.application.class.module_parent_name
      rescue StandardError
        "MyApp"
      end
    end
  end
end
