# frozen_string_literal: true

require "flodesk"
require "webmock/rspec"
require "tmpdir"
require "fileutils"
require "stringio"

# Block every real outbound connection. The suite must be hermetic: a spec that
# accidentally reaches api.flodesk.com would be slow, flaky, and could mutate a
# real account. WebMock raises on any unstubbed request.
WebMock.disable_net_connect!(allow_localhost: false)

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
