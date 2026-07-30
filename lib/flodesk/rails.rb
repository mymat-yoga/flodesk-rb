# frozen_string_literal: true

# Optional Rails integration.
#
# Loaded automatically when Rails is present, and never otherwise: the gem must
# work in a plain Ruby process and declares no runtime dependency on Rails or
# ActiveSupport.
require_relative "rails/railtie" if defined?(Rails::Railtie)
