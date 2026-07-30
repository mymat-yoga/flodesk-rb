# frozen_string_literal: true

RSpec.describe "Rails integration" do
  describe "optional loading" do
    it "does not define the Railtie when Rails::Railtie is absent" do
      # `railties` is a development dependency but is never required by the gem,
      # so the guard in lib/flodesk/rails.rb must leave the Railtie undefined.
      expect(defined?(Flodesk::Rails::Railtie)).to be_nil
    end

    it "loads and works fully without Rails" do
      expect { Flodesk::Client.new(api_key: "k") }.not_to raise_error
    end

    it "references no Rails constant from the core library" do
      core = Dir[File.expand_path("../../lib/flodesk/**/*.rb", __dir__)]
             .reject { |f| f.include?("/rails") || f.include?("test_helpers") }

      offenders = core.select { |f| File.read(f).match?(/(?<!Flodesk::)\bRails\./) }

      expect(offenders).to be_empty
    end

    it "does not require rails or activesupport from the core library" do
      core = Dir[File.expand_path("../../lib/flodesk/**/*.rb", __dir__)]
             .reject { |f| f.include?("/rails") || f.include?("test_helpers") }

      offenders = core.select { |f| File.read(f).match?(/^\s*require\s+["'](rails|active_support)/) }

      expect(offenders).to be_empty
    end
  end

  describe "the generator template" do
    let(:template) do
      File.read(
        File.expand_path(
          "../../lib/generators/flodesk/templates/initializer.rb.tt", __dir__
        )
      )
    end

    it "builds a client rather than configuring gem-level state" do
      expect(template).to include("Flodesk::Client.new")
      expect(template).not_to include("Flodesk.configure")
    end

    it "assigns the client to a host application constant" do
      expect(template).to match(/^FLODESK = /)
    end

    it "reads the api key from Rails credentials" do
      expect(template).to include("Rails.application.credentials.flodesk_api_key")
    end

    it "sets an app_name, since the API expects an identifying User-Agent" do
      expect(template).to include("app_name:")
    end

    it "contains no literal API key" do
      expect(template).not_to match(/fd_[a-zA-Z0-9]{10,}/)
    end

    it "is valid Ruby once the ERB placeholders are filled" do
      rendered = template.gsub(/<%=.*?%>/, "Placeholder")

      expect { RubyVM::AbstractSyntaxTree.parse(rendered) }.not_to raise_error
    end

    it "documents the rate limits and the absent reset header" do
      expect(template).to include("100 requests/minute")
      expect(template).to include("no rate-limit reset header")
    end
  end

  describe "the generator, actually run" do
    require "rails/generators"
    require "rails/generators/base"
    require_relative "../../lib/generators/flodesk/install_generator"

    around do |example|
      Dir.mktmpdir("flodesk-generator") do |dir|
        @destination = dir
        example.run
      end
    end

    def run_generator(behavior: :invoke, force: false)
      generator = Flodesk::Generators::InstallGenerator.new(
        [], { force: force }, destination_root: @destination, behavior: behavior
      )
      generator.shell = Thor::Shell::Basic.new
      capture_output { generator.invoke_all }
    end

    # The generator prints next steps; keep that out of the spec output.
    def capture_output
      original = $stdout
      $stdout = StringIO.new
      yield
      $stdout.string
    ensure
      $stdout = original
    end

    def initializer_path
      File.join(@destination, "config/initializers/flodesk.rb")
    end

    it "declares its template source" do
      expect(Flodesk::Generators::InstallGenerator.source_root).to end_with("templates")
    end

    it "creates config/initializers/flodesk.rb" do
      run_generator

      expect(File).to exist(initializer_path)
    end

    it "writes an initializer that builds a client from credentials" do
      run_generator

      contents = File.read(initializer_path)
      expect(contents).to include("Flodesk::Client.new")
      expect(contents).to include("Rails.application.credentials.flodesk_api_key")
    end

    it "renders the ERB placeholders" do
      run_generator

      expect(File.read(initializer_path)).not_to include("<%=")
    end

    it "produces syntactically valid Ruby" do
      run_generator

      expect { RubyVM::AbstractSyntaxTree.parse_file(initializer_path) }.not_to raise_error
    end

    it "writes no API key into the repository" do
      run_generator

      expect(File.read(initializer_path)).not_to match(/fd_[a-zA-Z0-9]{10,}/)
    end

    it "tells the user which credentials key to populate" do
      output = run_generator

      expect(output).to include("flodesk_api_key")
    end

    it "does not silently overwrite an existing initializer" do
      FileUtils.mkdir_p(File.dirname(initializer_path))
      File.write(initializer_path, "# hand-written, do not clobber\n")

      run_generator

      expect(File.read(initializer_path)).to include("hand-written, do not clobber")
    end

    it "says it skipped rather than failing silently" do
      FileUtils.mkdir_p(File.dirname(initializer_path))
      File.write(initializer_path, "# existing\n")

      output = run_generator

      expect(output).to match(/already exists/)
    end

    it "replaces the initializer when --force is given" do
      FileUtils.mkdir_p(File.dirname(initializer_path))
      File.write(initializer_path, "# hand-written\n")

      run_generator(force: true)

      contents = File.read(initializer_path)
      expect(contents).not_to include("hand-written")
      expect(contents).to include("Flodesk::Client.new")
    end

    it "can be run twice without error" do
      run_generator

      expect { run_generator }.not_to raise_error
      expect(File).to exist(initializer_path)
    end
  end
end
