# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/test_feature"

class RegistryTest < PhComposerTestCase
  Registry = PhComposer::Registry
  OBJECT = { "type" => "object" }.freeze

  # A feature assembled from a block, so each test states only the declarations it is about.
  def feature(name = "Probe", &install)
    Module.new do
      define_singleton_method(:install) { |registry| install.call(registry) }
      define_singleton_method(:name) { name }
    end
  end

  def refused(*features)
    error = assert_raises(PhComposer::RegistrationError) { Registry.install(features) }
    error.diagnostics
  end

  def test_registration_can_reuse_same_batch_or_installed_dependency_record_descriptor
    live = Registry.new
    first = Registry::Staging.new(live)
    scope = first.feature("probe", :contract_version => 1)
    target = PhComposer::Records::ReferenceTarget.new(
      :id => "probe.entity", :label => "Synthetic", :records => ->(_model) { [] }, :validate => ->(_record) { [] },
      :occurrence => { "type" => "object", "properties" => { "path" => { "type" => "array" } } }
    )
    scope.reference_target(target)
    assert_same target.descriptor, first.record_descriptor("probe.entity")
    assert_nil first.record_descriptor("probe.missing")
    live.reference_targets[target.id] = target
    second = Registry::Staging.new(live)
    assert_same target.descriptor, second.record_descriptor("probe.entity")
    assert_empty second.declared_reference_targets
  end

  # Registration checks the schema subset's values, not only its keywords.
  def test_malformed_schema_values_and_inconsistent_required_refuse
    bad = [
      { "type" => "object", "properties" => { "n" => { "type" => "integer", "minimum" => "one" } } },
      { "type" => "object", "properties" => { "n" => { "type" => "array", "minItems" => -1 } } },
      { "type" => "object", "properties" => { "n" => { "type" => "string", "enum" => [] } } },
      { "type" => "object", "additionalProperties" => false, "required" => ["missing"], "properties" => {} },
      { "type" => "object", "properties" => { "n" => { "type" => "number", "minimum" => 5, "maximum" => 1 } } },
      { "type" => "object", "properties" => { "n" => { "type" => "array", "minItems" => 3, "maxItems" => 1 } } },
      { "type" => "object", "properties" => { "n" => { "type" => "string", "enum" => [1] } } }
    ]
    bad.each_with_index do |params, index|
      diagnostics = refused(feature do |registry|
        registry.feature("probe.schema", :contract_version => 1)
                .query("probe.schema.read#{index}", :description => "Probe.", :params => params, :result => OBJECT,
                                                    :examples => [{}], :refuses => []) { {} }
      end)
      assert_equal ["registration.schema_invalid"], diagnostics.map(&:code).uniq, params.inspect
    end
  end

  def test_an_operation_needs_a_description_a_callable_handler_and_valid_examples
    params = { "type" => "object", "additionalProperties" => false, "required" => ["n"],
               "properties" => { "n" => { "type" => "integer" } } }
    cases = {
      "no description" => lambda do |scope|
        scope.query("probe.ops.a", :description => " ", :params => OBJECT, :result => OBJECT, :refuses => []) { {} }
      end,
      "no example" => lambda do |scope|
        scope.query("probe.ops.b", :description => "B.", :params => params, :result => OBJECT, :refuses => []) { {} }
      end,
      "invalid example" => lambda do |scope|
        scope.query("probe.ops.c", :description => "C.", :params => params, :result => OBJECT,
                                   :examples => [{ "n" => "one" }], :refuses => []) { {} }
      end,
      "not callable" => lambda do |scope|
        scope.query("probe.ops.d", :description => "D.", :params => OBJECT, :result => OBJECT, :refuses => []) { {} }
        scope.instance_variable_get(:@staging).declared_queries.last.handler = "not callable"
      end
    }
    cases.each do |label, declare|
      diagnostics = refused(feature { |registry| declare.call(registry.feature("probe.ops", :contract_version => 1)) })
      assert_equal ["registration.schema_invalid"], diagnostics.map(&:code).uniq, label
    end
  end

  def test_participants_and_menu_items_need_callable_handlers
    %i[declared_proposal_participants declared_menu_items].each do |collection|
      diagnostics = refused(feature do |registry|
        scope = registry.feature("probe.calls", :contract_version => 1)
        scope.proposal_participant("probe.calls.participant", **participant_contract) { |*_args| {} }
        scope.menu_item("probe.calls.item", :label => "Item", :menu => "Probe") { |_session| nil }
        scope.instance_variable_get(:@staging).public_send(collection).last.handler = "not callable"
      end)
      assert_equal ["registration.schema_invalid"], diagnostics.map(&:code).uniq, collection.to_s
    end
  end

  def test_an_operation_whose_params_accept_nothing_needs_no_example
    Registry.install([feature do |registry|
      registry.feature("probe.empty", :contract_version => 1)
              .query("probe.empty.read", :description => "Read.", :params => OBJECT, :result => OBJECT,
                                         :refuses => []) { {} }
    end])

    assert Registry.installed?("probe.empty")
  end

  def test_dynamic_context_menu_entries_are_rebuilt_for_current_session
    labels = ["First"]
    called = []
    Registry.install([feature do |registry|
      registry.feature("probe.menu", :contract_version => 1)
              .menu_entries("probe.menu.current", :menu => "Probe") do |read|
        labels.map do |label|
          PhComposer::Declarations::MenuEntry.new(:label => label, :handler => ->(current) { called << current })
        end.tap { assert_same PhComposer::Sessions.current, read.session }
      end
    end])
    refute PhComposer::Commands.install_feature_menus(UI::Menu.new("Global")).key?("Probe")
    menus = PhComposer::Commands.install_feature_menus(UI::Menu.new("Context"), :contextual => true)
    first = menus.fetch("Probe").entries.first
    assert_equal "First", first.first
    first.last.call
    assert_equal [PhComposer::Sessions.current], called
    labels.replace(["Second", "Third"])
    menus = PhComposer::Commands.install_feature_menus(UI::Menu.new("Context"), :contextual => true)
    assert_equal %w[Second Third], menus.fetch("Probe").entries.map(&:first)
    Sketchup.active_model = Sketchup::Model.new
    first.last.call
    assert_equal 1, called.length, "a catalog entry belongs to the session that built it"
  end

  def test_a_context_menu_tests_an_entry_provider_once
    tests = 0
    counted = ->(_read) { (tests += 1).positive? }
    Registry.install([feature do |registry|
      registry.feature("probe.menu", :contract_version => 1)
              .menu_entries("probe.menu.counted", :menu => "Probe", :available => counted) do
        [PhComposer::Declarations::MenuEntry.new(:label => "Counted", :handler => ->(_current) {})]
      end
    end])
    menus = PhComposer::Commands.install_feature_menus(UI::Menu.new("Context"), :contextual => true)
    assert_equal [["Counted", 1]], [[menus.fetch("Probe").entries.first.first, tests]]
  end

  def test_a_raising_menu_test_or_provider_omits_only_its_own_item
    Registry.install([feature do |registry|
      scope = registry.feature("probe.menu", :contract_version => 1)
      scope.menu_item("probe.menu.kept", :label => "Kept", :menu => "Probe") { |_session| nil }
      scope.menu_item("probe.menu.test", :label => "Test", :menu => "Probe",
                                         :available => ->(_read) { raise "broken test" }) { |_session| nil }
      scope.menu_entries("probe.menu.provider", :menu => "Probe") { |_read| raise "broken provider" }
    end])
    menus = PhComposer::Commands.install_feature_menus(UI::Menu.new("Context"), :contextual => true)
    assert_equal ["Kept"], menus.fetch("Probe").entries.map(&:first)
  end

  def test_a_code_is_a_described_noun_condition_and_one_feature_owns_each_noun
    diagnostics = refused(feature do |registry|
      one = registry.feature("probe.one", :contract_version => 1)
      one.code("probe.taken", :description => "First.")
      one.code("Probe", :description => "Not a code.")
      one.code("probe.taken", :description => "Again.")
      one.code("target.mine", :description => "A foundation noun.")
      registry.feature("probe.two", :contract_version => 1).code("probe.other", :description => "Same noun.")
    end)
    assert_equal %w[registration.schema_invalid registration.duplicate_id registration.schema_invalid
                    registration.duplicate_id], diagnostics.map(&:code)
    assert_equal "probe.one", diagnostics.last.dependency
  end

  def test_refuses_names_a_declared_or_foundation_code_once_and_not_a_common_one
    declare = lambda do |refuses|
      feature do |registry|
        scope = registry.feature("probe.refuses", :contract_version => 1)
        scope.code("probe.refused", :description => "A declared refusal.")
        scope.query("probe.refuses.read", :description => "Read.", :params => OBJECT, :result => OBJECT,
                                          :refuses => refuses) { {} }
      end
    end
    Registry.install([declare.call(%w[probe.refused target.not_found library.row_semantic_invalid])])
    assert_equal %w[probe.refused target.not_found library.row_semantic_invalid],
                 Registry.current.queries.fetch("probe.refuses.read").refuses

    { "an undeclared code" => %w[probe.unheard], "a repeat" => %w[target.not_found target.not_found],
      "a common code" => %w[session.busy], "a dispatch-only code" => %w[access.user_required] }
      .each do |label, refuses|
      Registry.reset
      diagnostics = refused(declare.call(refuses))
      assert_equal ["registration.schema_invalid"], diagnostics.map(&:code), label
      assert_includes diagnostics.first.message, "probe.refuses.read", label
      assert_includes diagnostics.first.message, refuses.first, label
    end
  end

  # A feature's code reaches only operations of that feature or one requiring it.
  def test_refuses_names_another_features_code_only_through_a_requirement
    owner = feature do |registry|
      registry.feature("probe.owner", :contract_version => 1).code("probe.gone", :description => "Gone.")
    end
    reader = lambda do |requires|
      feature do |registry|
        registry.feature("probe.reader", :contract_version => 1, :requires => requires)
                .query("probe.reader.read", :description => "Read.", :params => OBJECT, :result => OBJECT,
                                            :refuses => %w[probe.gone]) { {} }
      end
    end
    diagnostics = refused(owner, reader.call([]))
    assert_equal ["probe.reader.read refuses lists probe.gone, which belongs to probe.owner; probe.reader must " \
                  "require it."], diagnostics.map(&:message)
    Registry.reset
    Registry.install([owner, reader.call(["probe.owner"])])
    assert_equal %w[probe.gone], Registry.current.queries.fetch("probe.reader.read").refuses
  end

  # Every operation says what it refuses with; `[]` is the explicit "nothing beyond the common sets".
  def test_an_operation_without_refuses_is_refused
    diagnostics = refused(feature do |registry|
      registry.feature("probe.silent", :contract_version => 1)
              .query("probe.silent.read", :description => "Read.", :params => OBJECT, :result => OBJECT) { {} }
    end)
    assert_equal ["probe.silent.read needs refuses, a list of codes."], diagnostics.map(&:message)

    Registry.reset
    diagnostics = refused(feature do |registry|
      scope = registry.feature("probe.silent", :contract_version => 1)
      scope.query("probe.silent.read", :description => "Read.", :params => OBJECT, :result => OBJECT,
                                       :refuses => []) { {} }
      scope.instance_variable_get(:@staging).declared_queries.last.refuses = nil
    end)
    assert_equal ["probe.silent.read needs refuses, a list of codes."], diagnostics.map(&:message)
  end

  def test_dynamic_context_menu_provider_and_entries_are_validated
    diagnostics = refused(feature do |registry|
      registry.feature("probe.menu", :contract_version => 1).menu_entries("probe.menu.missing", :menu => "Probe")
    end)
    assert_equal ["registration.schema_invalid"], diagnostics.map(&:code)
    Registry.install([feature do |registry|
      registry.feature("probe.menu", :contract_version => 1)
              .menu_entries("probe.menu.invalid", :menu => "Probe") { |_read| ["invalid entry"] }
    end])
    assert_raises(PhComposer::InternalError) do
      PhComposer::Commands.install_feature_menus(UI::Menu.new("Context"), :contextual => true)
    end
  end

  def test_published_declarations_are_frozen
    Registry.install([feature do |registry|
      registry.feature("probe.frozen", :contract_version => 1)
              .query("probe.frozen.read", :description => "Read.", :params => OBJECT, :result => OBJECT,
                                          :refuses => []) { {} }
    end])
    query = Registry.current.queries.fetch("probe.frozen.read")

    assert_raises(FrozenError) { query.result = { "type" => "array" } }
    assert_raises(FrozenError) { query.params["type"] = "array" }
    assert_raises(FrozenError) { query.refuses << "target.not_found" }
  end

  def test_reference_target_requires_callable_provider_and_pure_validator
    target = PhComposer::Records::ReferenceTarget.new(:id => "outside.feature.object", :label => "Object",
                                                      :records => nil, :validate => nil)
    diagnostics = refused(feature do |registry|
      registry.feature("outside.feature", :contract_version => 1).reference_target(target)
    end)

    assert_equal ["registration.schema_invalid"], diagnostics.map(&:code)
    refute Registry.installed?("outside.feature")
    refute Registry.current.reference_targets.key?(target.id)
  end

  def test_a_core_reference_to_an_unregistered_kind_refuses_the_target
    target = PhComposer::Records::ReferenceTarget.new(
      :id => "outside.feature.object", :label => "Object", :records => ->(_model) { [] },
      :validate => ->(_record) { [] },
      :references => [PhComposer::Records::Reference.new(:key => "owner_id", :target_kind => "missing.feature.kind",
                                                         :cardinality => "one", :required => false)]
    )
    diagnostics = refused(feature do |registry|
      registry.feature("outside.feature", :contract_version => 1).reference_target(target)
    end)

    assert_equal [["registration.missing_dependency", "missing.feature.kind"]],
                 diagnostics.map { |diagnostic| [diagnostic.code, diagnostic.dependency] }
  end

  def test_unregistered_reference_target_refuses_the_extension_batch
    extension = PhComposer::Records::Extension.new(
      :namespace => "outside.feature.links", :schema_version => 1,
      :references => [{ "path" => "$.entity", "target_kind" => "missing.feature.object", "cardinality" => "one" }]
    )
    diagnostics = refused(feature do |registry|
      registry.feature("outside.feature", :contract_version => 1).extension(extension)
    end)

    assert_equal ["registration.missing_dependency"], diagnostics.map(&:code)
    refute Registry.installed?("outside.feature")
  end

  def test_a_valid_feature_publishes_every_declaration
    Registry.install([TestFeature])

    assert Registry.installed?("test.fixture")
    assert Registry.current.actions.key?("test.fixture.update_parts")
    assert Registry.current.record_kinds.key?("test.fixture.part")
    assert_equal "test.fixture", Registry.current.owner_of("test.fixture.review")
  end

  def test_a_duplicate_name_names_both_owners_and_publishes_nothing_from_the_batch
    diagnostics = refused(
      feature { |r| r.feature("probe.one", :contract_version => 1).query("probe.one.read", **read) { {} } },
      feature { |r| r.feature("probe.two", :contract_version => 1).query("probe.one.read", **read) { {} } }
    )

    codes = diagnostics.map(&:code)
    assert_includes codes, "registration.duplicate_id"
    duplicate = diagnostics.find { |diagnostic| diagnostic.code == "registration.duplicate_id" }
    assert_equal ["probe.two", "probe.one"], [duplicate.owner, duplicate.dependency]
    refute Registry.installed?("probe.one")
    refute Registry.current.queries.key?("probe.one.read")
  end

  def test_a_record_kind_claimed_by_two_features_names_both
    kind = PhComposer::Records::RecordKind.new(:id => "probe.one.kind", :label => "Kind", :schema_version => 1,
                                               :id_prefix => "pok", :fields => [])
    diagnostics = refused(
      feature { |r| r.feature("probe.one", :contract_version => 1).record_kind(kind) },
      feature { |r| r.feature("probe.two", :contract_version => 1).record_kind(kind) }
    )

    duplicate = diagnostics.find { |diagnostic| diagnostic.code == "registration.duplicate_id" }
    assert_equal "probe.one.kind is declared by both probe.one and probe.two.", duplicate.message
  end

  def test_a_refused_kind_does_not_register_its_dictionary
    kind = PhComposer::Records::RecordKind.new(:id => "probe.bad.kind", :label => "Bad", :schema_version => 1,
                                               :id_prefix => "pbk", :fields => [])
    refused(feature { |r| r.feature("probe.bad", :contract_version => 2).record_kind(kind) })

    refute_includes PhComposer::Dictionaries.names, kind.store.dictionary
  end

  def test_a_second_install_of_the_same_feature_is_refused_and_adds_no_observer
    Registry.install([TestFeature, subscriber])
    count = Registry.current.subscriptions.length

    diagnostics = refused(subscriber)

    assert_includes diagnostics.map(&:code), "registration.duplicate_id"
    assert_equal count, Registry.current.subscriptions.length
  end

  def test_a_published_host_event_subscription_receives_session_events
    received = []
    Registry.install([subscriber(received)])

    PhComposer::Sessions.current.host_event(:selection_changed)

    assert_equal [:selection_changed], received
  end

  def test_a_feature_can_publish_a_named_proposal_participant
    handler = ->(_request, _proposal) { {} }
    participant = feature("Participant") do |registry|
      registry.feature("test.participant", :contract_version => 1)
              .proposal_participant("test.participant.retire", **participant_contract, &handler)
    end

    Registry.install([participant])

    declaration = Registry.current.proposal_participants.fetch("test.participant.retire")
    assert_equal "test.participant", declaration.owner
    assert_same handler, declaration.handler
  end

  def test_missing_dependencies_cycles_and_contract_majors_are_diagnosed
    diagnostics = refused(
      feature { |r| r.feature("probe.alpha", :contract_version => 1, :requires => ["probe.beta"]) },
      feature { |r| r.feature("probe.beta", :contract_version => 1, :requires => ["probe.alpha"]) },
      feature { |r| r.feature("probe.gamma", :contract_version => 1, :requires => ["probe.absent"]) },
      feature { |r| r.feature("probe.delta", :contract_version => 2) }
    )

    by_code = diagnostics.group_by(&:code)
    assert_equal ["probe.alpha"], by_code.fetch("registration.cycle").map(&:owner)
    assert_equal ["probe.absent"], by_code.fetch("registration.missing_dependency").map(&:dependency)
    assert_equal ["probe.delta"], by_code.fetch("registration.contract_major").map(&:owner)
  end

  def test_names_must_sit_under_their_feature
    diagnostics = refused(feature { |r|
                            r.feature("probe.one", :contract_version => 1).query("other.read", **read) {
                              {}
                            }
                          })

    assert_equal ["registration.schema_invalid"], diagnostics.map(&:code)
  end

  # Every identifier is at most Registry::ID_MAX_BYTES, so a discover row always fits one agent reply.
  def test_an_identifier_at_the_cap_installs_and_one_byte_longer_refuses_the_batch
    cap = Registry::ID_MAX_BYTES
    long_id = "probe.#{'f' * (cap - 6)}"
    name = "probe.one.#{'r' * (cap - 10)}"
    code = "probe_#{'c' * (cap - 14)}.missing"
    Registry.install([feature { |r| r.feature(long_id, :contract_version => 1) },
                      feature do |r|
                        scope = r.feature("probe.one", :contract_version => 1)
                        scope.code(code, :description => "At the cap.")
                        scope.query(name, **read) { {} }
                      end])
    assert_equal [cap, cap, cap], [long_id, name, code].map(&:bytesize)
    assert Registry.installed?(long_id)

    Registry.reset
    diagnostics = refused(feature { |r| r.feature("#{long_id}g", :contract_version => 1) },
                          feature do |r|
                            scope = r.feature("probe.two", :contract_version => 1)
                            scope.code("probe_#{'c' * (cap - 13)}.missing", :description => "Over the cap.")
                            scope.query("probe.two.#{'r' * (cap - 9)}", **read) { {} }
                          end)
    assert_equal ["registration.schema_invalid"] * 3, diagnostics.map(&:code)
    assert(diagnostics.all? { |item| item.message.end_with?("#{cap + 1} bytes; an identifier is at most #{cap}.") })
    refute Registry.installed?("probe.two")
  end

  def test_schemas_confirmation_references_sections_and_host_events_are_checked
    kind = PhComposer::Records::RecordKind.new(
      :id => "probe.one.part", :label => "Part", :schema_version => 1, :id_prefix => "prp",
      :fields => [PhComposer::Records::Reference.new(:key => "other_id", :target_kind => "probe.absent.kind",
                                                     :cardinality => "one")]
    )
    diagnostics = refused(feature do |r|
      scope = r.feature("probe.one", :contract_version => 1)
      scope.record_kind(kind)
      scope.query("probe.one.bad", :description => "", :params => { "type" => "text" }, :result => OBJECT,
                                   :refuses => []) { {} }
      scope.action("probe.one.ask", :description => "", :params => OBJECT, :result => OBJECT, :undo_name => "Ask",
                                    :side_effects => "", :confirmation => "always", :refuses => []) { {} }
      scope.snapshot_section("probe.one.view", :query => "probe.one.absent")
      scope.on_host_event(:model_closed) { nil }
    end)

    messages = diagnostics.map(&:message).join("\n")
    assert_match(/probe.one.bad params: \$ has unknown type "text"/, messages)
    assert_match(/probe.one.bad params must be an object/, messages)
    assert_match(/only "none" is supported/, messages)
    assert_match(/refers to record kind probe.absent.kind/, messages)
    assert_match(/projects query probe.one.absent/, messages)
    assert_match(/subscribes to :model_closed, which needs a known host event/, messages)
  end

  def test_an_install_that_raises_is_a_diagnostic_not_a_crash
    diagnostics = refused(feature("Broken") { |_r| raise ArgumentError, "typo" })

    assert_equal ["Broken could not install: typo"], diagnostics.map(&:message)
  end

  # The native menus are a contribution seam like the others: an outside feature declares an item
  # and it reaches SketchUp's own menus, and the viewport context menu, with no line in `shell/`.
  def test_an_outside_feature_reaches_the_native_menus_without_a_line_in_shell
    reached = []
    Registry.install([feature do |registry|
      registry.feature("outside.probe", :contract_version => 1)
              .menu_item("outside.probe.go", :label => "Go", :menu => "Probe",
                                             :state => ->(_session) { MF_CHECKED }) { |session| reached << session }
    end])
    PhComposer::Commands.install
    menu = PhComposer::Commands.feature_menus.fetch("Probe")

    menu.entries.find { |entry| entry.is_a?(Array) && entry.first == "Go" }.last.call

    assert_equal [PhComposer::Sessions.current], reached
    assert_equal MF_CHECKED, menu.validation_procs.values.first.call
  end

  # A view command is registered, described and dispatched like a query, and an outside feature
  # declares one the same way a built-in does.
  def test_an_outside_feature_registers_a_view_command_and_it_is_described_as_one
    Registry.install([feature do |registry|
      registry.feature("outside.probe", :contract_version => 1)
              .view_command("outside.probe.look", :description => "Look.", :params => OBJECT,
                                                  :result => OBJECT, :refuses => []) { |_request| {} }
    end])

    assert Registry.current.view_commands.key?("outside.probe.look")
    assert_equal "outside.probe", Registry.current.owner_of("outside.probe.look")
    assert_equal "view_command", PhComposer::API.describe(:name => "outside.probe.look").fetch("kind")
    assert_includes PhComposer::API.discover.fetch("view_commands").map { |one| one.fetch("name") },
                    "outside.probe.look"
  end

  def test_a_view_command_with_no_handler_refuses_the_whole_batch
    probe = feature do |registry|
      registry.feature("outside.probe", :contract_version => 1)
              .view_command("outside.probe.look", :description => "Look.", :params => OBJECT, :result => OBJECT,
                                                  :refuses => [])
    end

    error = assert_raises(PhComposer::RegistrationError) { Registry.install([probe]) }

    assert_includes error.diagnostics.map(&:code), "registration.schema_invalid"
    refute Registry.current.view_commands.key?("outside.probe.look")
  end

  def test_a_menu_item_without_a_submenu_name_refuses_the_whole_batch
    probe = feature do |registry|
      registry.feature("outside.probe", :contract_version => 1)
              .menu_item("outside.probe.go", :label => "Go", :menu => nil) { |_session| nil }
    end

    error = assert_raises(PhComposer::RegistrationError) { Registry.install([probe]) }

    assert_includes error.diagnostics.map(&:code), "registration.schema_invalid"
    refute Registry.current.menu_items.key?("outside.probe.go")
  end

  def test_a_store_dictionary_outside_the_prefix_refuses_the_batch_and_publishes_nothing
    store = CountingStore.new("outside.records")
    before = published
    diagnostics = refused(kind_feature("probe.store", store))

    assert_equal ["registration.schema_invalid"], diagnostics.map(&:code)
    assert_match(/probe\.store\.kind store dictionary "outside\.records"/, diagnostics.first.message)
    refute Registry.installed?("probe.store")
    assert_equal before, published
    assert_nil Registry.current.owner_of("probe.store.kind")
    assert_equal({ :dictionary => 1 }, store.calls, "the getter is read once and nothing else is called")
  end

  def test_a_store_missing_any_engine_method_is_named
    %i[dictionary ids read write delete].each do |method|
      store = CountingStore.new("ph_composer.records.probe", without: method)
      diagnostics = refused(kind_feature("probe.store", store))
      assert_equal 1, diagnostics.length, method.to_s
      assert_match(/store must answer #{method}\./, diagnostics.first.message)
    end
  end

  def test_a_store_dictionary_getter_that_raises_is_a_diagnostic
    store = CountingStore.new(nil) { raise ArgumentError, "no name" }
    diagnostics = refused(kind_feature("probe.store", store))
    assert_equal ["registration.schema_invalid"], diagnostics.map(&:code)
    assert_match(/store dictionary raised ArgumentError/, diagnostics.first.message)
  end

  def test_a_kind_may_keep_a_legacy_dictionary_name_under_the_prefix
    Registry.install([kind_feature("probe.legacy", CountingStore.new("ph_composer.face_assignment.legacy"))])
    assert_includes PhComposer::Dictionaries.names, "ph_composer.face_assignment.legacy"
  end

  def test_one_bad_kind_publishes_nothing_of_any_feature_or_subscription_in_the_batch
    received = []
    good = feature("Good") do |registry|
      scope = registry.feature("probe.good", :contract_version => 1)
      scope.query("probe.good.read", :description => "Read.", :params => OBJECT, :result => OBJECT,
                                     :refuses => []) { {} }
      scope.on_host_event(:selection_changed) { |_session| received << :selection_changed }
    end
    before = published
    refused(good, kind_feature("probe.bad", CountingStore.new("outside.records"), "Bad"))

    assert_equal before, published
    PhComposer::Sessions.current.host_event(:selection_changed)
    assert_empty received
  end

  def test_a_dictionary_getter_that_changes_its_answer_publishes_the_admitted_name
    answers = %w[ph_composer.records.admitted outside.records]
    store = CountingStore.new(nil) { answers.shift || "outside.records" }
    Registry.install([kind_feature("probe.changing", store)])
    assert_includes PhComposer::Dictionaries.names, "ph_composer.records.admitted"
    refute_includes PhComposer::Dictionaries.names, "outside.records"
    assert_equal 1, store.calls[:dictionary]
    assert_equal "probe.changing", Registry.current.owner_of("probe.changing.kind")
  end

  def test_an_install_from_inside_an_install_is_refused_and_the_next_install_succeeds
    before = published
    nested = kind_feature("probe.nested", CountingStore.new("ph_composer.records.nested"), "Nested")
    store = CountingStore.new(nil) do
      Registry.install([nested])
      "ph_composer.records.outer"
    end
    error = assert_raises(PhComposer::InternalError) { Registry.install([kind_feature("probe.outer", store)]) }
    assert_match(/while another install was running/, error.message)
    assert_equal before, published

    Registry.install([nested])
    assert Registry.installed?("probe.nested")
  end

  private

  def read
    { :description => "Read.", :params => OBJECT, :result => OBJECT, :refuses => [] }
  end

  def participant_contract
    { :description => "Probe.", :params => OBJECT, :result => OBJECT, :refuses => [] }
  end

  def subscriber(received = [])
    @subscriber ||= feature("Subscriber") do |r|
      r.feature("probe.subscriber", :contract_version => 1).on_host_event(:selection_changed) do |_session|
        received << :selection_changed
      end
    end
  end

  # A store the engine could call: every method counts its calls, and `dictionary` answers `name`.
  class CountingStore
    attr_reader :calls

    def initialize(name, without: nil, &getter)
      @name = name
      @getter = getter
      @calls = Hash.new(0)
      singleton_class.send(:undef_method, without) if without
    end

    def dictionary
      @calls[:dictionary] += 1
      @getter ? @getter.call : @name
    end

    %i[ids read write delete].each do |method|
      define_method(method) { |*_args| @calls[method] += 1 }
    end
  end

  def stored_kind(id, store)
    PhComposer::Records::RecordKind.new(:id => id, :label => "Kind", :schema_version => 1, :id_prefix => "prb",
                                        :fields => [], :store => store)
  end

  def kind_feature(feature_id, store, name = "Probe")
    feature(name) do |registry|
      scope = registry.feature(feature_id, :contract_version => 1)
      scope.record_kind(stored_kind("#{feature_id}.kind", store))
      scope.query("#{feature_id}.read", :description => "Read.", :params => OBJECT, :result => OBJECT,
                                        :refuses => []) { {} }
    end
  end

  def published
    current = Registry.current
    [current.features.keys, current.queries.keys, current.record_kinds.keys, PhComposer::Dictionaries.names.dup,
     current.subscriptions.length]
  end
end
