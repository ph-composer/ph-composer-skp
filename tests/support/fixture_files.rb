# frozen_string_literal: true

# Generated goldens are written by `make fixtures` and compared by every other run. Writing and
# comparing are separate methods so a run can never assert against a file it has just rewritten,
# and the mode is read once at load rather than per call.
module FixtureFiles
  UUID_PATTERN = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/.freeze
  WRITING = ENV["PHC_WRITE_FIXTURES"] == "1"

  # Writes when the run is a `make fixtures` run, compares otherwise. The owning test names the
  # golden; exactly one test may own each file (`make fixtures` lists the owners).
  def write_or_compare(path, value)
    FixtureFiles::WRITING ? write_fixture(path, value) : assert_fixture(path, value)
  end

  # Only an actual change is written: `make fixtures` is a change-detection target, and rewriting
  # every golden on every run moves ten mtimes on a synced working tree for nothing.
  def write_fixture(path, value)
    contents = fixture_contents(value)
    if !File.exist?(path) || File.read(path) != contents
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, contents)
      warn("fixtures: wrote #{relative_fixture_path(path)}")
    end
    assert true
  end

  def assert_fixture(path, value)
    assert File.exist?(path), "#{relative_fixture_path(path)} is missing; run `make fixtures`"
    assert_equal File.read(path), fixture_contents(value),
                 "#{relative_fixture_path(path)} is stale; run `make fixtures`"
  end

  def normalize_uuids(value, uuids = {})
    case value
    when Hash
      value.each_with_object({}) { |(key, item), result| result[key] = normalize_uuids(item, uuids) }
    when Array
      value.map { |item| normalize_uuids(item, uuids) }
    when String
      value.gsub(UUID_PATTERN) { |uuid| uuids[uuid] ||= "uuid-#{uuids.length + 1}" }
    else
      value
    end
  end

  private

  # An empty container is the one place `JSON.pretty_generate` is not stable across gem versions:
  # json 2.6.3, which Ruby 3.2.2 ships, writes `[]` over three lines, and 2.10 and later write it
  # over one. A golden whose bytes depend on which `json` RubyGems happened to activate goes stale
  # on a `gem install` that had nothing to do with this repo, and reports it as "run make
  # fixtures". Collapsing here pins the layout instead. A raw newline never appears inside a JSON
  # string, which is escaped as `\n`, so this cannot reach a value.
  #
  # Floats differ the same way: 2.6.3 writes `Float#to_s` (`3.2e-05`), later gems write a float
  # below 1e-4 as a decimal (`0.000032`). Every float that is a whole line's value is rewritten
  # with `Float#to_s`, which is what 2.6.3 writes, so the bytes no longer depend on the gem.
  def fixture_contents(value)
    generated = JSON.pretty_generate(sort_keys(normalize_uuids(value)))
    generated = generated.gsub(/\[\n\s*\]/, "[]").gsub(/\{\n\s*\}/, "{}")
    generated.gsub(FLOAT_LINE) { "#{Regexp.last_match(1)}#{Float(Regexp.last_match(2))}#{Regexp.last_match(3)}" } + "\n"
  end

  # A pretty-printed line whose value is a float: optional key, the number, optional comma.
  FLOAT_LINE = /^(\s*(?:"(?:[^"\\\n]|\\.)*": )?)(-?\d+(?:\.\d+(?:[eE][+-]?\d+)?|[eE][+-]?\d+))(,?)$/.freeze
  private_constant :FLOAT_LINE

  def relative_fixture_path(path)
    path.sub(File.expand_path("../..", __dir__) + "/", "")
  end

  def sort_keys(value)
    case value
    when Hash
      value.keys.sort.each_with_object({}) { |key, result| result[key] = sort_keys(value[key]) }
    when Array
      value.map { |item| sort_keys(item) }
    else
      value
    end
  end
end
