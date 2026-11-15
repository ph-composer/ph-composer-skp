# frozen_string_literal: true

# The contributor walkthrough (planning/archive/phase-00-foundation/CONTRACTS.md) as a script: two clients
# drive the example feature through PhComposer::API with the panel closed. Every step records what
# happened and whether it is what the contract says. Run it against an open Model:
#
#   ExampleWalkthrough.run                      # the active Model's session
#   ExampleWalkthrough.run(session_id: "...")   # any session discovery lists
#
# It writes records into that Model, each change one Undo step.
module ExampleWalkthrough
  API = PhComposer::API
  PART = ExampleFoundation::PART
  ID = ExampleFoundation::ID

  module_function

  def run(session_id: nil)
    found = API.discover
    session = session_id || found.fetch("sessions").find { |row| row.fetch("active") }&.fetch("id")
    raise ArgumentError, "No open Model session." unless session

    steps = []
    first = API.connect(:session_id => session)
    second = API.connect(:session_id => session)

    created = invoke(first, "#{ID}.create_parts", create_params, 1, revision(first))
    sill, head = created.dig("value", "part_ids")
    steps << step("create", created, created["effect"] == "committed")

    read = parts(first, [sill])
    read_revision = read.fetch("revision")
    steps << step("read", read, read.dig("value", "records", 0, "values", "length_mm") == 1200)

    edit = { "edits" => [{
      "id" => sill, "values" => { "length_mm" => 950 }, "expected_values" => { "length_mm" => 1200 },
      "review" => { "review_status" => "draft", "checked_against" => head }
    }] }
    updated = invoke(first, "#{ID}.update_parts", edit, 2, read_revision)
    steps << step("update", updated, updated["effect"] == "committed" && updated["revision"] > read_revision)

    back = parts(first, [sill]).dig("value", "records", 0)
    steps << step("read back", updated, back.dig("values", "length_mm") == 950)

    stale = invoke(second, "#{ID}.update_parts", { "edits" => [{ "id" => sill, "values" => { "length_mm" => 800 } }] },
                   1, read_revision)
    unchanged = parts(first, [sill]).dig("value", "records", 0, "values", "length_mm") == 950
    steps << step("stale second client", stale, stale["code"] == "revision.stale" && unchanged)

    retried = invoke(first, "#{ID}.update_parts", edit, 2, read_revision)
    steps << step("retry", retried, retried == updated)

    # Every kind's user_data is written by the core metadata action, guarded by the maps last read.
    tagged = invoke(first, "ph_composer.records.update_metadata", tag_params(sill, back), 3, revision(first))
    back = parts(first, [sill]).dig("value", "records", 0)
    steps << step("tag", tagged, back.dig("user_data", "example_org", "review_status") == "needs_site_check")

    duplicated = invoke(first, "#{ID}.duplicate_parts", { "ids" => [sill, head] }, 4, revision(first))
    mapping = duplicated.dig("value", "mapping") || {}
    copy = parts(first, [mapping[sill]].compact).dig("value", "records", 0) || {}
    remapped = copy.dig("extension_data", ExampleFoundation::REVIEW, "payload", "checked_against") == mapping[head]
    shared = copy.dig("values", "definition_id") == back.dig("values", "definition_id")
    steps << step("duplicate", duplicated, remapped && shared && copy["user_data"] == back["user_data"])

    summary = API.query(:context => first, :name => "#{ID}.summary")
    steps << step("summary", summary, summary.dig("value", "parts") >= 4)

    { "session" => session, "passed" => steps.all? { |row| row["passed"] }, "steps" => steps }
  end

  Field = PhComposer::Records::Field
  NOTES = "example.notes"
  NOTE = "#{NOTES}.note"

  # A store the example writes itself rather than DictionaryStore: registration admits any object that
  # answers the engine's five methods with a dictionary under ph_composer. It is checked, not called,
  # at install.
  class NoteStore
    def initialize
      @records = PhComposer::Records::DictionaryStore.new(NOTE)
    end

    def dictionary
      @records.dictionary
    end

    def ids(model)
      @records.ids(model)
    end

    def read(model, id)
      @records.read(model, id)
    end

    def write(model, record)
      @records.write(model, record)
    end

    def delete(model, id)
      @records.delete(model, id)
    end
  end

  # The registration contract as an outside contributor meets it (context/CONTRACTS.md, "Registration"):
  # a second feature with its own store and a nested reference installs through the same call as the
  # built-ins; editing the builders it kept afterwards changes nothing published; a further
  # contribution with a store outside the prefix is refused whole, and the first keeps working.
  def registration
    steps = []
    builders = notes_builders
    PhComposer::Registry.install([notes_feature(builders)]) unless PhComposer::Registry.installed?(NOTES)
    described = API.describe(:name => NOTE)
    installed = described["owner"] == NOTES && described.dig("references", 0, "key") == "rows[].part_id"
    steps << { "step" => "outside install", "passed" => installed }

    builders.fetch(:text)["minLength"] = 100
    builders.fetch(:rows).target_kind.replace("example.elsewhere")
    after = API.describe(:name => NOTE)
    steps << { "step" => "builders edited after install",
               "passed" => after.dig("values", "properties", "text", "minLength") == 1 &&
                           after.dig("references", 0, "target_kind") == PART }

    error = begin
      PhComposer::Registry.install([refused_feature])
      nil
    rescue PhComposer::RegistrationError => refusal
      refusal
    end
    still = API.query(:context => API.connect(:session_id => active_session), :name => "#{ID}.summary")
    refused = error&.diagnostics&.map(&:code) == ["registration.schema_invalid"] &&
              !PhComposer::Registry.installed?("example.refused") &&
              !PhComposer::Dictionaries.names.include?("outside.notes")
    steps << { "step" => "refused contribution", "passed" => refused && still["status"] == "completed" }
    { "passed" => steps.all? { |row| row["passed"] }, "steps" => steps }
  end

  # A dependent feature's action calls the example's participant twice inside its own proposal: preview
  # writes nothing, invoke commits both parts as one Undo step, and the parts read back.
  def composition(session_id: nil)
    context = API.connect(:session_id => session_id || active_session)
    created = invoke(context, "#{ID}.create_parts", create_params, next_sequence(context), revision(context))
    definition = created.dig("value", "definition_id")
    params = { "definition_id" => definition, "length_mm" => 2100 }
    before = API.query(:context => context, :name => "#{ID}.summary").dig("value", "parts")
    preview = API.preview(:context => context, :name => "#{ExampleKit::ID}.add_pair", :params => params)
    previewed = API.query(:context => context, :name => "#{ID}.summary").dig("value", "parts")
    added = invoke(context, "#{ExampleKit::ID}.add_pair", params, next_sequence(context), revision(context))
    ids = added.dig("value", "part_ids") || []
    back = parts(context, ids).dig("value", "records") || []
    steps = [
      step("preview", preview, preview["status"] == "completed" && previewed == before),
      step("invoke", added, added["effect"] == "committed" && ids.length == 2),
      step("read back", added, back.map { |row| row.dig("values", "label") }.sort == ["Left jamb", "Right jamb"] &&
                               back.all? { |row| row.dig("values", "definition_id") == definition })
    ]
    { "passed" => steps.all? { |row| row["passed"] }, "steps" => steps, "part_ids" => ids }
  end

  # Each walkthrough connects its own caller, so it starts its own sequence.
  def next_sequence(context)
    (@sequences ||= {}.compare_by_identity)[context] = @sequences.fetch(context, 0) + 1
  end

  def notes_builders
    { :text => { "type" => "string", "minLength" => 1 },
      :rows => PhComposer::Records::Reference.new(:key => "rows[].part_id".dup, :target_kind => PART.dup,
                                                  :cardinality => "one") }
  end

  def notes_feature(builders)
    Module.new do
      define_singleton_method(:name) { "ExampleNotes" }
      define_singleton_method(:install) do |registry|
        rows = { "type" => "array", "items" => { "type" => "object",
                                                 "properties" => { "part_id" => { "type" => "string" } } } }
        kind = PhComposer::Records::RecordKind.new(
          :id => NOTE, :label => "Example note", :schema_version => 1, :id_prefix => "exn", :store => NoteStore.new,
          :fields => [Field.new(:key => "text", :schema => builders.fetch(:text), :required => true),
                      Field.new(:key => "rows", :schema => rows, :required => false)],
          :references => [builders.fetch(:rows)]
        )
        registry.feature(NOTES, :contract_version => 1, :requires => [ID]).record_kind(kind)
      end
    end
  end

  def refused_feature
    # Every engine method is present; only the dictionary is outside the prefix.
    store = Struct.new(:dictionary, :ids, :read, :write, :delete).new("outside.notes")
    Module.new do
      define_singleton_method(:name) { "ExampleRefused" }
      define_singleton_method(:install) do |registry|
        registry.feature("example.refused", :contract_version => 1).record_kind(
          PhComposer::Records::RecordKind.new(:id => "example.refused.note", :label => "Refused",
                                              :schema_version => 1, :id_prefix => "exr", :fields => [], :store => store)
        )
      end
    end
  end

  def active_session
    API.discover.fetch("sessions").find { |row| row.fetch("active") }.fetch("id")
  end

  def create_params
    { "definition_label" => "Frame",
      "parts" => [{ "label" => "Sill", "length_mm" => 1200 }, { "label" => "Head", "length_mm" => 1200 }] }
  end

  # The whole map to keep, with the part's user_data and extension_data as read.
  def tag_params(id, read)
    { "updates" => [{ "reference" => { "kind" => PART, "id" => id },
                      "user_data" => read.fetch("user_data").merge(
                        "example_org" => { "review_status" => "needs_site_check" }
                      ),
                      "expected_metadata" => read.slice("user_data", "extension_data") }] }
  end

  def invoke(context, name, params, sequence, expected_revision)
    API.invoke(:context => context, :name => name, :params => params,
               :request => { "sequence" => sequence, "expected_revision" => expected_revision })
  end

  def parts(context, ids)
    API.query(:context => context, :name => "ph_composer.records.list", :params => { "kind" => PART, "ids" => ids })
  end

  def revision(context)
    API.query(:context => context, :name => "#{ID}.summary").fetch("revision")
  end

  def step(name, outcome, passed)
    { "step" => name, "status" => outcome["status"], "code" => outcome["code"], "effect" => outcome["effect"],
      "revision" => outcome["revision"], "passed" => passed ? true : false }
  end
end
