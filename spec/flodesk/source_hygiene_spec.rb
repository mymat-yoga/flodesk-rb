# frozen_string_literal: true

# Guards against source corruption that is invisible in an editor.
#
# A raw NUL byte once reached `lib/flodesk/webhooks/event.rb` through an
# automated edit. The file still parsed, every test passed, and the line rendered
# as `join(" ")` — but git classified the file as binary, so it produced no
# diffs and no blame. Only `git merge` output revealed it, as `Bin 0 -> 2184`.
RSpec.describe "source hygiene" do
  let(:root) { File.expand_path("../..", __dir__) }

  # Everything git tracks, so the check covers specs and fixtures too.
  let(:tracked_files) do
    Dir.chdir(root) { `git ls-files -z`.split("\0") }
       .map { |relative| File.join(root, relative) }
       .select { |path| File.file?(path) }
  end

  it "tracks files to check" do
    expect(tracked_files.size).to be > 50
  end

  it "contains no raw control bytes in any tracked file" do
    # Tab (9), newline (10), vertical tab (11), form feed (12) and carriage
    # return (13) are legitimate; everything below 32 outside that range is not.
    offenders = tracked_files.filter_map do |path|
      bytes = File.binread(path).each_byte.with_index.select do |byte, _|
        byte < 9 || (byte > 13 && byte < 32)
      end
      next if bytes.empty?

      "#{path.delete_prefix("#{root}/")}: byte 0x#{bytes.first.first.to_s(16)} " \
        "at offset #{bytes.first.last}"
    end

    expect(offenders).to be_empty
  end

  it "keeps every Ruby source file valid UTF-8" do
    ruby_files = tracked_files.select { |f| f.end_with?(".rb", ".rbs", ".gemspec", ".tt") }

    invalid = ruby_files.reject { |f| File.read(f).valid_encoding? }

    expect(invalid).to be_empty
  end

  it "parses every Ruby source file" do
    ruby_files = tracked_files.select { |f| f.end_with?(".rb") }
    # The generator template is ERB, not plain Ruby, so it is excluded.
    unparseable = ruby_files.reject do |f|
      RubyVM::AbstractSyntaxTree.parse_file(f)
      true
    rescue SyntaxError
      false
    end

    expect(unparseable).to be_empty
  end

  it "ends every tracked text file with a newline" do
    text_files = tracked_files.select { |f| f.end_with?(".rb", ".rbs", ".md", ".yml", ".gemspec") }

    missing = text_files.reject { |f| File.binread(f).end_with?("\n") }
                        .map { |f| f.delete_prefix("#{root}/") }

    expect(missing).to be_empty
  end
end
