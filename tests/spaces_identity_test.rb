# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"

# Copies of Spaces, Volumes and Floor Segments: the duplicate_identity finding and Make independent
# (context/CONTRACTS.md, "Geometry records and occurrence references"). A native copy is modelled as the
# host makes it: a new Group over the same entities, carrying the original's instance dictionaries.
class SpacesIdentityTest < PhComposerTestCase
  include SpaceFixtures

  API = PhComposer::API

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @volume = volume_group(111, volume_record("A"), [floor_face(112, rectangle(0, 0, 2, 2), segment_record("A"))])
    @space = space_group(110, space_record("S", :number => "1").merge("user_data" => { "note" => "kept" }), [@volume])
    @zone = zone_group(100, "Z", [@space])
    @model.entities << @zone
  end

  def native_copy(group, persistent_id, parent)
    copy = Sketchup::Group.new(persistent_id, group.entities, {}, :transformation => group.transformation,
                                                                  :locked => group.locked?)
    Array(group.attribute_dictionaries).each do |dictionary|
      dictionary.each { |key, value| copy.set_attribute(dictionary.name, key, value) }
    end
    parent.entities << copy
    treat_duplicates_as_existing(@model)
    copy
  end

  def spaces
    API.query(:context => @context, :name => "ph_composer.spaces.all").fetch("value").fetch("spaces")
  end

  def codes(row)
    row.fetch("findings").map { |finding| finding["code"] }
  end

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end

  def make_independent(reference)
    invoke("ph_composer.spaces.make_independent", "reference" => reference)
  end

  def test_a_copied_space_raises_the_blocking_finding_on_every_record_of_both_occurrences
    native_copy(@space, 120, @zone)
    rows = spaces
    assert_equal [[100, 110], [100, 120]], rows.map { |row| row.dig("reference", "entity_path") }
    rows.each do |row|
      finding = row.fetch("findings").find { |item| item["code"] == "space.duplicate_identity" }
      assert finding["blocks_export"]
      assert_includes finding["message"], "Make independent"
      assert_equal "make_independent", finding["repair"], "the row offers the repair without reading its words"
      assert_includes codes(row.dig("volumes", 0)), "space.duplicate_identity"
      assert_includes codes(row.dig("volumes", 0, "floor_segments", 0)), "space.duplicate_identity"
      [row.dig("volumes", 0), row.dig("volumes", 0, "floor_segments", 0)].each do |child|
        inner = child.fetch("findings").find { |item| item["code"] == "space.duplicate_identity" }
        refute inner.key?("repair"), "the copy's contents are repaired with their Space, not on their own"
        assert_includes inner["message"], "on its Space"
      end
    end
  end

  def test_a_copied_volume_and_a_copied_floor_segment_raise_the_finding_on_both
    native_copy(@volume, 113, @space)
    @volume.entities << floor_face(114, rectangle(2, 0, 1, 1), segment_record("A"))
    volumes = spaces.first.fetch("volumes")
    assert_equal(2, volumes.count { |volume| codes(volume).include?("space.duplicate_identity") })
    segments = volumes.first.fetch("floor_segments")
    assert_equal [true, true], segments.map { |segment| codes(segment).include?("space.duplicate_identity") }
    copied = segments.map { |segment| segment["findings"].find { |item| item["code"] == "space.duplicate_identity" } }
    assert(copied.all? { |finding| finding["message"].include?("on its Volume") && !finding.key?("repair") },
           "a copied Volume's Floor Segments are repaired with the Volume, which offers it")
    assert_equal "make_independent",
                 volumes.first["findings"].find { |item| item["code"] == "space.duplicate_identity" }["repair"]
  end

  def test_make_independent_rewrites_the_named_copy_in_one_step_and_leaves_the_original
    copy = native_copy(@space, 120, @zone)
    before = @model.operations.length
    result = make_independent("space_id" => "spc_SSSSSSSSSSSS", "entity_path" => [100, 120])
    assert_equal "completed", result["status"], result.inspect
    assert_equal before + 1, @model.operations.length
    original, independent = spaces
    assert_equal %w[spc_SSSSSSSSSSSS vol_AAAAAAAAAAAA fsg_AAAAAAAAAAAA], ids(original)
    assert_equal "1", original.dig("values", "number")
    refute_equal ids(original), ids(independent)
    assert_equal ids(independent).uniq, ids(independent)
    assert_equal "2", independent.dig("values", "number")
    refute_equal "flr_AAAAAAAAAAAA", independent.dig("volumes", 0, "values", "floor_id")
    assert_equal({ "note" => "kept" }, independent["user_data"])
    refute PhComposer::Spaces::Occurrences.shared_storage?(copy), "the copy has storage of its own"
    [original, independent].each do |row|
      refute_includes codes(row), "space.duplicate_identity"
      refute_includes codes(row.dig("volumes", 0, "floor_segments", 0)), "space.duplicate_identity"
    end
  end

  def test_naming_the_original_rewrites_the_original
    native_copy(@space, 120, @zone)
    result = make_independent("space_id" => "spc_SSSSSSSSSSSS", "entity_path" => [100, 110])
    assert_equal "completed", result["status"], result.inspect
    original, copy = spaces
    refute_equal "spc_SSSSSSSSSSSS", original["id"]
    assert_equal "spc_SSSSSSSSSSSS", copy["id"]
  end

  def test_make_independent_on_a_copied_volume_and_a_copied_floor_segment
    native_copy(@volume, 113, @space)
    result = make_independent("volume_id" => "vol_AAAAAAAAAAAA", "entity_path" => [100, 110, 113])
    assert_equal "completed", result["status"], result.inspect
    volumes = spaces.first.fetch("volumes")
    assert_equal 2, volumes.map { |volume| volume["id"] }.uniq.length
    assert_equal 2, volumes.map { |volume| volume.dig("floor_segments", 0, "id") }.uniq.length
    @volume.entities << floor_face(114, rectangle(2, 0, 1, 1), segment_record("A"))
    result = make_independent("floor_segment_id" => "fsg_AAAAAAAAAAAA", "entity_path" => [100, 110, 111, 114])
    assert_equal "completed", result["status"], result.inspect
    segments = spaces.first.fetch("volumes").find { |volume| volume.dig("reference", "entity_path").last == 111 }
                     .fetch("floor_segments")
    assert_equal 2, segments.map { |segment| segment["id"] }.uniq.length
  end

  # D-UD-2: the Space Floor's map travels with its Volume, so a copy made independent keeps an independent one
  # under its new floor_id.
  def test_a_volume_made_independent_keeps_an_independent_copy_of_its_floors_map
    note = { "example_org" => { "finish" => "screed" } }
    SPACES::VOLUME_STORE.write(@volume, volume_record("A").merge("floor_user_data" => note))
    native_copy(@volume, 113, @space)
    shared = invoke("ph_composer.spaces.update_metadata", "updates" => [{
      "reference" => { "floor_id" => "flr_AAAAAAAAAAAA", "entity_path" => [100, 110, 113] }, "user_data" => {},
      "expected_metadata" => { "user_data" => note, "extension_data" => {} }
    }])
    assert_equal %w[refused target.ambiguous], shared.values_at("status", "code"), shared.inspect
    result = make_independent("volume_id" => "vol_AAAAAAAAAAAA", "entity_path" => [100, 110, 113])
    assert_equal "completed", result["status"], result.inspect
    floors = spaces.first.fetch("volumes").map { |volume| volume.fetch("floor") }
    assert_equal [note, note], floors.map { |floor| floor.fetch("user_data") }
    assert_equal 2, floors.map { |floor| floor.dig("reference", "floor_id") }.uniq.length
    copy = floors.find { |floor| floor.dig("reference", "entity_path").last == 113 }
    written = invoke("ph_composer.spaces.update_metadata", "updates" => [{
      "reference" => copy.fetch("reference"), "user_data" => { "copy" => true },
      "expected_metadata" => { "user_data" => note, "extension_data" => {} }
    }])
    assert_equal "completed", written["status"], written.inspect
    assert_equal note, SPACES::VOLUME_STORE.read(@volume).fetch("floor_user_data"), "the original is untouched"
  end

  # A Space inside a Group copied with it shares storage above the Space: the finding says so, and Make
  # independent refuses rather than making the parent unique.
  def test_a_space_repeated_through_shared_storage_has_no_repair
    wrapper = Sketchup::Group.new(130, Sketchup::Entities.new([@space]))
    @zone.entities.delete(@space)
    @zone.entities << wrapper
    native_copy(wrapper, 131, @zone)
    finding = spaces.first.fetch("findings").find { |item| item["code"] == "space.duplicate_identity" }
    assert_includes finding["message"], "Draw the Space directly"
    refute finding.key?("repair"), "shared storage has no repair to offer"
    before = @model.operations.length
    result = make_independent("space_id" => "spc_SSSSSSSSSSSS", "entity_path" => [100, 131, 110])
    assert_equal %w[refused target.shared_definition], result.values_at("status", "code")
    assert_equal before, @model.operations.length
  end

  def test_an_occurrence_with_its_own_identity_refuses
    result = make_independent("space_id" => "spc_SSSSSSSSSSSS", "entity_path" => [100, 110])
    assert_equal %w[refused space.identity_unique], result.values_at("status", "code")
  end

  # A Volume only the copy holds keeps its id, so a reference to it from outside the copy still resolves.
  def test_a_record_only_the_copy_holds_keeps_its_id_and_the_references_to_it
    extension = register_extension
    copy = native_copy(@space, 120, @zone).make_unique
    copy.entities << volume_group(140, volume_record("U", :number => 2), [])
    other = space_group(150, space_record("O", :number => "9").merge(
      "extension_data" => { extension.namespace => extension.envelope("volume" => "vol_UUUUUUUUUUUU") }
    ), [])
    @zone.entities << other
    result = make_independent("space_id" => "spc_SSSSSSSSSSSS", "entity_path" => [100, 120])
    assert_equal "completed", result["status"], result.inspect
    assert_equal(["vol_UUUUUUUUUUUU"], spaces.find { |row| row.dig("reference", "entity_path") == [100, 120] }
                                             .fetch("volumes").map { |volume| volume["id"] } & ["vol_UUUUUUUUUUUU"])
    refute_includes result["value"]["ids"].map { |row| row["before"] }, "vol_UUUUUUUUUUUU"
  end

  # An id held only inside the target keeps a holder: the named Space is renamed and the nested Space that
  # shares its id keeps it, so a reference from outside still resolves.
  def test_an_id_held_only_inside_the_target_keeps_a_holder
    extension = register_extension
    nested = space_group(180, space_record("S", :number => "1"), [])
    @space.entities << nested
    treat_duplicates_as_existing(@model)
    other = space_group(150, space_record("O", :number => "9").merge(
      "extension_data" => { extension.namespace => extension.envelope("volume" => "vol_AAAAAAAAAAAA") }
    ), [])
    @zone.entities << other
    result = make_independent("space_id" => "spc_SSSSSSSSSSSS", "entity_path" => [100, 110])
    assert_equal "completed", result["status"], result.inspect
    held = PhComposer::Spaces::Occurrences.scan(@model).spaces.map { |space| space.record["id"] }
    assert_includes held, "spc_SSSSSSSSSSSS"
    refute_equal "spc_SSSSSSSSSSSS", PhComposer::Spaces::SPACE_STORE.read(@space)["id"]
    assert_equal "vol_AAAAAAAAAAAA", PhComposer::Spaces::VOLUME_STORE.read(@volume)["id"], "held only here"
  end

  # Two Volumes in the copy share an id no one outside holds: one keeps it, one is renamed, and a payload
  # naming that id cannot say which it meant.
  def test_a_payload_naming_an_id_several_records_in_the_copy_hold_refuses
    extension = register_extension
    copy = native_copy(@space, 120, @zone).make_unique
    copy.entities << volume_group(141, volume_record("U", :number => 2), [])
    copy.entities << volume_group(142, volume_record("U", :number => 3), [])
    record = PhComposer::Spaces::SPACE_STORE.read(copy)
    PhComposer::Spaces::SPACE_STORE.write(copy, record.merge(
      "extension_data" => { extension.namespace => extension.envelope("volume" => "vol_UUUUUUUUUUUU") }
    ))
    result = make_independent("space_id" => "spc_SSSSSSSSSSSS", "entity_path" => [100, 120])
    assert_equal %w[refused reference.invalid], result.values_at("status", "code")
  end

  def test_an_unsupported_payload_in_the_copy_refuses_with_its_copy_rule
    record = volume_record("A").merge("extension_data" => { "outside.vendor" => { "schema_version" => 1 } })
    PhComposer::Spaces::VOLUME_STORE.write(@volume, record)
    native_copy(@space, 120, @zone)
    result = make_independent("space_id" => "spc_SSSSSSSSSSSS", "entity_path" => [100, 120])
    assert_equal %w[refused copy.rule_missing], result.values_at("status", "code")
  end

  # Two copied Volumes sharing an id inside the copy each keep a reference to themselves.
  def test_repeated_records_in_the_copy_each_keep_their_own_self_reference
    extension = register_extension
    record = volume_record("A").merge("extension_data" => {
      extension.namespace => extension.envelope("volume" => "vol_AAAAAAAAAAAA")
    })
    PhComposer::Spaces::VOLUME_STORE.write(@volume, record)
    native_copy(@volume, 113, @space)
    native_copy(@space, 120, @zone)
    result = make_independent("space_id" => "spc_SSSSSSSSSSSS", "entity_path" => [100, 120])
    assert_equal "completed", result["status"], result.inspect
    volumes = spaces.find { |row| row.dig("reference", "entity_path") == [100, 120] }.fetch("volumes")
    assert_equal 2, volumes.map { |volume| volume["id"] }.uniq.length
    volumes.each do |volume|
      assert_equal volume["id"], volume.dig("extension_data", extension.namespace, "payload", "volume")
    end
  end

  # Every reference the action reports resolves after storage isolation replaced the copy's entities.
  def test_the_reported_references_resolve_after_isolation
    native_copy(@space, 120, @zone)
    result = make_independent("space_id" => "spc_SSSSSSSSSSSS", "entity_path" => [100, 120])
    scan = PhComposer::Spaces::Occurrences.scan(@model)
    references = result.fetch("affected").map { |row| row.fetch("reference") }
    assert_equal 3, references.length
    references.each do |reference|
      assert PhComposer::Spaces::Resolve.occurrence(scan, reference, :mutable => true), reference.inspect
    end
  end

  # A restorable step puts back the native name with the record, for a follow-up that cannot abort.
  def test_restore_puts_back_the_records_and_the_space_name
    copy = native_copy(@space, 120, @zone)
    copy.name = "1"
    scan = PhComposer::Spaces::Occurrences.scan(@model)
    target = scan.spaces.find { |space| space.path == [100, 120] }
    counter = 0
    plan = PhComposer::Spaces::IdentityPlan.build(scan, target, :number => "2", :allocate => lambda { |prefix|
      "#{prefix}_#{format('%012d', counter += 1)}"
    }, :catalog => PhComposer::Registry.current.catalog, :engine => nil)
    step = PhComposer::Spaces::IdentityStep.new(:plan => plan, :target => target)
    step.apply(@model, {})
    assert_equal "2", copy.name
    step.restore
    assert_equal "1", copy.name
    assert_equal "spc_SSSSSSSSSSSS", PhComposer::Spaces::SPACE_STORE.read(copy)["id"]
  end

  # A Space in a single component placement has no copy, yet no storage of its own: the finding, and a
  # refusal that says so rather than calling its identity unique.
  def test_a_space_in_a_single_component_has_the_finding_and_refuses_as_shared
    @zone.entities.delete(@space)
    definition = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([@space]))
    @zone.entities << Sketchup::ComponentInstance.new(160, definition)
    finding = spaces.first.fetch("findings").find { |item| item["code"] == "space.duplicate_identity" }
    assert_includes finding["message"], "Draw the Space directly"
    result = make_independent("space_id" => "spc_SSSSSSSSSSSS", "entity_path" => [100, 160, 110])
    assert_equal %w[refused target.shared_definition], result.values_at("status", "code")
  end

  def test_an_orphan_volume_sharing_an_id_has_the_finding_too
    @model.entities << volume_group(170, volume_record("A"), [])
    strays = API.query(:context => @context, :name => "ph_composer.spaces.all").dig("value", "findings")
    assert_equal %w[space.volume_orphan space.duplicate_identity], strays.map { |finding| finding["code"] }
    assert_includes codes(spaces.first.dig("volumes", 0)), "space.duplicate_identity"
  end

  private

  def register_extension
    references = [{ "path" => "$.volume", "target_kind" => PhComposer::Spaces::VOLUME_KIND, "cardinality" => "one" }]
    extension = PhComposer::Records::Extension.new(:namespace => "test.space_copy.links", :schema_version => 1,
                                                   :references => references)
    PhComposer::Registry.install([Module.new do
      define_singleton_method(:install) do |registry|
        registry.feature("test.space_copy", :contract_version => 1, :requires => ["ph_composer.spaces"])
                .extension(extension)
      end
    end])
    extension
  end

  def ids(row)
    [row["id"], row.dig("volumes", 0, "id"), row.dig("volumes", 0, "floor_segments", 0, "id")]
  end
end
