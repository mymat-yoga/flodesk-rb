# frozen_string_literal: true

module Flodesk
  module Rails
    # Registers the gem's Rails integration.
    #
    # Deliberately minimal: it makes the generator discoverable and nothing else.
    # There is no initializer hook that configures the gem, because the gem holds
    # no global state — `rails g flodesk:install` scaffolds a client constant in
    # the host application instead.
    class Railtie < ::Rails::Railtie
      railtie_name "flodesk"

      generators do
        require_relative "../../generators/flodesk/install_generator"
      end
    end
  end
end
