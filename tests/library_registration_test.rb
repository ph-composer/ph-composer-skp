# frozen_string_literal: true

require_relative "test_helper"

class LibraryRegistrationTest < PhComposerTestCase
  Registry = PhComposer::Registry
  D = PhComposer::Declarations
  OBJECT = { "type" => "object" }.freeze

  def callback
    D::LibraryCallback.new(:params => { "type" => "object", "properties" => { "id" => { "type" => "string" } } },
                           :result => { "type" => "object" }, :refuses => [], :handler => ->(*_arguments) { {} })
  end

  def adapter(wire_kind = "widgets")
    schema = { "type" => "object", "properties" => { "name" => { "type" => "string" } } }
    wire = { "type" => "object", "required" => ["id"],
             "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" } } }
    D::LibraryAdapter.new(:wire_kind => wire_kind.dup, :wire_version => 1, :fingerprint_version => 1,
                          :wire_schema => wire, :display_label => ->(mapped) { mapped.fetch("name") },
                          :mapped_schema => PhComposer::DeepCopy.call(schema),
                          :fingerprint_fields => ["name"], :map => ->(row) { row }, :reverse => ->(row) {
                                                                                                  row
                                                                                                },
                          :fingerprint => ->(_row) {
                                            "digest"
                                          }, :local_read => callback, :create => callback, :replace => callback)
  end

  def feature(id = "test.library", kind_adapter = adapter, requires: [], &extra)
    Module.new do
      define_singleton_method(:name) { "LibraryProbe" }
      define_singleton_method(:install) do |registry|
        scope = registry.feature(id, :contract_version => 1, :requires => requires)
        scope.record_kind(PhComposer::Records::RecordKind.new(:id => "#{id}.widget", :label => "Widget",
                                                              :schema_version => 1, :id_prefix => "wid", :fields => []))
        scope.library_kind("#{id}.wire", :contract_version => 1, :record_kind => "#{id}.widget",
                                         :adapter => kind_adapter) if kind_adapter
        extra.call(scope) if extra
      end
    end
  end

  def refused(*features)
    error = assert_raises(PhComposer::RegistrationError) { Registry.install(features) }
    refute Registry.installed?("test.library")
    error.diagnostics
  end

  def test_valid_batch_publishes_both_seams_without_running_factory_or_callbacks
    value = adapter
    value.assign = callback
    factories = 0
    probe = feature("test.library", value) do |scope|
      scope.library_provider("test.library.file", :contract_version => 1, :kinds => ["widgets"]) do |_id, _config|
        factories += 1
        raise "Registration must not create a provider"
      end
    end
    Registry.install([probe])
    assert_equal 0, factories
    assert_equal "test.library", Registry.current.owner_of("test.library.file")
    assert_equal "test.library.widget", Registry.current.library_kinds.fetch("test.library.wire").record_kind
    assert Registry.current.library_kinds.fetch("test.library.wire").adapter.assign
    assert_empty Sketchup.active_model.operations
  end

  def test_provider_can_precede_adapter_in_same_batch_and_have_no_feature_dependency
    provider = feature("test.provider", nil) do |scope|
      scope.library_provider("test.provider.file", :contract_version => 1, :kinds => ["widgets"]) { Object.new }
    end
    Registry.install([provider, feature])
    assert_empty Registry.current.features.fetch("test.provider").requires
    assert_equal ["widgets"], Registry.current.library_providers.fetch("test.provider.file").kinds
  end

  def test_wildcard_provider_accepts_new_adapters_without_changing_its_declaration
    kinds = ["*".dup]
    provider = feature("test.provider", nil) do |scope|
      scope.library_provider("test.provider.file", :contract_version => 1, :kinds => kinds) { Object.new }
    end
    Registry.install([provider])
    published = Registry.current.library_providers.fetch("test.provider.file")
    Registry.install([feature("test.new_kind", adapter("new_widgets"))])
    assert_same published, Registry.current.library_providers.fetch("test.provider.file")
    assert_equal "new_widgets", Registry.current.library_kinds.fetch("test.new_kind.wire").adapter.wire_kind
    kinds.first.replace("changed")
    kinds << "other"
    assert_equal ["*"], published.kinds
    assert published.kinds.frozen?
    assert published.kinds.first.frozen?
  end

  def test_wildcard_cannot_mix_with_named_kinds_or_repeat
    [["*", "widgets"], ["widgets", "*"], ["*", "*"]].each do |kinds|
      diagnostics = refused(feature do |scope|
        scope.library_provider("test.library.file", :contract_version => 1, :kinds => kinds) {}
      end)
      assert_includes diagnostics.map(&:code), "registration.schema_invalid"
      refute Registry.current.library_providers.key?("test.library.file")
    end
  end

  def test_published_metadata_and_schemas_are_detached_frozen_copies
    value = adapter
    kinds = ["widgets"]
    Registry.install([feature("test.library", value) do |scope|
      scope.library_provider("test.library.file", :contract_version => 1, :kinds => kinds) { Object.new }
    end])
    published = Registry.current.library_kinds.fetch("test.library.wire")
    provider = Registry.current.library_providers.fetch("test.library.file")
    value.wire_kind.replace("changed")
    value.wire_schema["properties"]["name"]["type"] = "number"
    value.mapped_schema["properties"].clear
    value.fingerprint_fields << "extra"
    value.create.params["properties"]["id"]["type"] = "number"
    value.create.refuses << "record.unreadable"
    kinds << "other"
    assert_equal "widgets", published.adapter.wire_kind
    assert_equal "string", published.adapter.wire_schema.dig("properties", "name", "type")
    assert_equal ["name"], published.adapter.mapped_schema.fetch("properties").keys
    assert_equal ["name"], published.adapter.fingerprint_fields
    assert_equal "string", published.adapter.create.params.dig("properties", "id", "type")
    assert_empty published.adapter.create.refuses
    assert published.adapter.create.refuses.frozen?
    assert_equal ["widgets"], provider.kinds
    assert published.frozen?
    assert published.adapter.frozen?
    assert published.adapter.create.frozen?
    assert published.adapter.create.params.fetch("properties").frozen?
    assert provider.frozen?
    assert_same value.map, published.adapter.map
    refute value.map.frozen?, "Publishing metadata must not freeze contributor callable state"
  end

  def test_callback_refusal_lists_reject_invalid_unknown_common_dispatch_and_duplicate_codes
    [nil, "record.unreadable", [1], ["widget.unknown"], ["params.invalid"], ["request.unknown_operation"],
     %w[record.unreadable record.unreadable]].each do |codes|
      value = adapter
      value.create.refuses = codes
      diagnostics = refused(feature("test.library", value))
      assert diagnostics.any? { |item| item.message.include?("create.refuses") }, diagnostics.inspect
      refute Registry.current.library_kinds.key?("test.library.wire")
    end
  end

  def test_callback_foreign_noun_requires_owner_and_accepts_dependency_in_either_batch_order
    owner = feature("test.owner", nil) { |scope| scope.code("widget.blocked", :description => "Widget blocked.") }
    value = adapter
    value.create.refuses = ["widget.blocked".dup]
    diagnostics = refused(owner, feature("test.library", value))
    assert diagnostics.any? { |item| item.message.include?("test.library must require it") }
    refute Registry.installed?("test.owner"), "Invalid callbacks must refuse the complete batch"
    [true, false].each do |owner_first|
      Registry.reset
      consumer = feature("test.library", value, :requires => ["test.owner"])
      Registry.install(owner_first ? [owner, consumer] : [consumer, owner])
      published = Registry.current.library_kinds.fetch("test.library.wire").adapter.create.refuses
      assert_equal ["widget.blocked"], published
      assert published.first.frozen?
    end
    value.create.refuses.first.replace("changed")
    assert_equal ["widget.blocked"], Registry.current.library_kinds.fetch("test.library.wire").adapter.create.refuses
  end

  def test_duplicate_declaration_ids_and_wire_kinds_refuse_the_complete_batch
    diagnostics = refused(feature, feature("test.other"))
    assert_includes diagnostics.map(&:code), "registration.duplicate_id"
    refute Registry.current.library_kinds.key?("test.library.wire")
    refute Registry.current.library_kinds.key?("test.other.wire")
    diagnostics = refused(feature do |scope|
      2.times { scope.library_provider("test.library.file", :contract_version => 1, :kinds => ["widgets"]) {} }
    end)
    assert_includes diagnostics.map(&:code), "registration.duplicate_id"
    refute Registry.current.library_providers.key?("test.library.file")
  end

  def test_duplicate_wire_kind_against_live_registry_refuses_without_changing_live_entries
    Registry.install([feature("test.existing")])
    original = Registry.current.library_kinds.fetch("test.existing.wire")
    names = Registry.current.library_kinds.keys
    assert_includes refused(feature).map(&:code), "registration.duplicate_id"
    assert_same original, Registry.current.library_kinds.fetch("test.existing.wire")
    assert_equal names, Registry.current.library_kinds.keys
  end

  def test_missing_or_foreign_record_kind_refuses_even_with_declared_dependency
    ["missing.kind", "test.other.widget"].each do |record_kind|
      probe = feature("test.library", nil, :requires => ["test.other"]) do |scope|
        scope.library_kind("test.library.wire", :contract_version => 1, :record_kind => record_kind,
                                                :adapter => adapter)
      end
      diagnostics = refused(feature("test.other", nil), probe)
      assert diagnostics.any? { |item| item.message.include?(record_kind) }
    end
  end

  def test_unsupported_versions_refuse_before_publishing
    %i[wire_version fingerprint_version].each do |part|
      value = adapter
      value[part] = 2
      assert_includes refused(feature("test.library", value)).map(&:code), "registration.contract_major"
    end
    diagnostics = refused(feature("test.library", nil) do |scope|
      scope.library_kind("test.library.wire", :contract_version => 2,
                                              :record_kind => "test.library.widget", :adapter => adapter)
      scope.library_provider("test.library.file", :contract_version => 3, :kinds => ["widgets"]) {}
    end)
    assert_equal 2, diagnostics.count { |item| item.code == "registration.contract_major" }
  end

  def test_entity_reference_inventory_is_not_a_copyable_catalog_kind
    diagnostics = refused(feature("test.library", nil) do |scope|
      target = PhComposer::Records::ReferenceTarget.new(:id => "test.library.entity", :label => "Entity",
                                                        :records => ->(_model) { [] }, :validate => ->(_record) {
                                                                                                      []
                                                                                                    })
      scope.reference_target(target)
      scope.library_kind("test.library.wire", :contract_version => 1,
                                              :record_kind => target.id, :adapter => adapter)
    end)
    assert_includes diagnostics.map(&:code), "registration.missing_dependency"
    refute Registry.current.reference_targets.key?("test.library.entity")
  end

  def test_provider_requires_callable_factory_and_unique_known_wire_kinds
    [[], ["widgets", "widgets"], ["unknown"], ["Bad kind"], "widgets"].each do |kinds|
      diagnostics = refused(feature do |scope|
        scope.library_provider("test.library.file", :contract_version => 1, :kinds => kinds) {}
      end)
      assert diagnostics.any? { |item| item.subject == "test.library.file" }, kinds.inspect
    end
    assert_includes refused(feature do |scope|
      scope.library_provider("test.library.file", :contract_version => 1, :kinds => ["widgets"])
    end).map(&:code), "registration.schema_invalid"
  end

  def test_adapter_schemas_pure_methods_and_callbacks_are_validated
    mutations = [->(a) { a.wire_schema = nil }, ->(a) { a.mapped_schema = { "type" => "array" } },
                 ->(a) { a.map = nil }, ->(a) { a.reverse = false }, ->(a) { a.fingerprint = "digest" },
                 ->(a) { a.local_read = nil }, ->(a) { a.create = {} }, ->(a) { a.replace.handler = false },
                 ->(a) { a.create.params = { "type" => "string" } }, ->(a) {
                                                                       a.local_read.result = { "type" => "bad" }
                                                                     },
                 ->(a) { a.assign = {} }, ->(a) { a.fingerprint_fields = [] },
                 ->(a) { a.fingerprint_fields = ["name", "name"] }, ->(a) { a.fingerprint_fields = ["unknown"] },
                 ->(a) { a.wire_kind = "Bad kind" }]
    mutations.each do |mutate|
      value = adapter
      mutate.call(value)
      assert_includes refused(feature("test.library", value)).map(&:code), "registration.schema_invalid"
    end
    assert_includes refused(feature("test.library", nil) do |scope|
      scope.library_kind("test.library.wire", :contract_version => 1,
                                              :record_kind => "test.library.widget", :adapter => {})
    end).map(&:code), "registration.schema_invalid"
  end

  def test_a_wire_kind_longer_than_the_identifier_cap_is_refused
    cap = Registry::ID_MAX_BYTES
    Registry.install([feature("test.library", adapter("w" * cap))])
    assert_equal cap, Registry.current.library_kinds.fetch("test.library.wire").adapter.wire_kind.bytesize
    Registry.reset
    assert_equal ["#{'w' * 80}... is #{cap + 1} bytes; an identifier is at most #{cap}."],
                 refused(feature("test.library", adapter("w" * (cap + 1)))).map(&:message)
  end

  # An example a callback publishes is params it accepts; discovery shows the assign callback's to agents.
  def test_callback_examples_must_meet_their_params
    malformed = adapter
    malformed.create.params = { "properties" => {} }
    malformed.create.examples = [{}]
    assert_includes refused(feature("test.library", malformed)).map(&:code), "registration.schema_invalid"
    value = adapter
    value.create.examples = [{ "id" => "one", "open" => Float::INFINITY }]
    assert(refused(feature("test.library", value)).any? { |item| item.message.include?("not a finite number") })
    [{}, [1], [{ "id" => 7 }]].each do |examples|
      value = adapter
      value.create.examples = examples
      diagnostics = refused(feature("test.library", value))
      assert diagnostics.any? { |item| item.message.include?("create example") }, diagnostics.inspect
    end
    value = adapter
    value.assign = callback.tap { |assign| assign.examples = [{ "id" => "one" }] }
    Registry.install([feature("test.library", value)])
    described = PhComposer::API.describe(:name => "test.library.wire")
    assert_equal [true, []], [described.dig("assignment", "supported"), described.dig("assignment", "examples")]
  end
end
