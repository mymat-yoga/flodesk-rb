# frozen_string_literal: true

require "time"

module Flodesk
  # Turns raw JSON values into useful Ruby ones.
  #
  # Every coercion here passes unrecognized input through unchanged rather than
  # raising. Flodesk can add an enum member or change a format at any time, and
  # a client that raises on an unfamiliar value would break working code for a
  # change that does not actually affect the caller.
  module Coercion
    module_function

    # Converts a documented enum value to a Symbol. Values outside `allowed`
    # are returned as-is, so a newly introduced Flodesk value cannot break an
    # existing caller.
    def enum(value, allowed)
      return nil if value.nil?

      allowed.include?(value.to_s) ? value.to_s.to_sym : value
    end

    # Parses an ISO 8601 timestamp to a Time, passing unparseable input through.
    def time(value)
      return nil if value.nil?
      return value unless value.is_a?(String)

      begin
        Time.iso8601(value)
      rescue ArgumentError
        value
      end
    end

    # Builds an array of value objects, tolerating a missing or empty list.
    def array_of(klass, value)
      return [] unless value.is_a?(Array)

      value.filter_map { |item| klass.from(item) }.freeze
    end

    # Custom field values are typed `string` throughout the API, so keys and
    # values pass through intact.
    def string_hash(value)
      return {} unless value.is_a?(Hash)

      snapshot(value)
    end

    # An immutable copy of a payload.
    #
    # Copied rather than frozen in place: `.from` is public, so freezing the
    # argument would be a side effect on data the caller still owns and could
    # break code that reuses the hash afterwards. The copy also means a later
    # caller mutation cannot change what the value object reports.
    #
    # Recursive, so nested hashes and arrays are copied and frozen too: a
    # top-level-only copy would still hand back references the caller could
    # mutate underneath a supposedly immutable object.
    def snapshot(value)
      case value
      when Hash then value.transform_values { |v| snapshot(v) }.freeze
      when Array then value.map { |v| snapshot(v) }.freeze
      else value
      end
    end
  end
end
