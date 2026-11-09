# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"

# Spaces inside a copied Zone become independent with the Zone, in its one proposal and Undo step
# (context/CONTRACTS.md, "Compound proposals"; context/EXTENSIBILITY.md, "Records inside a Zone
# occurrence"). A native copy is modelled as the host makes it: a Group over the same entities, carrying
# the original's instance dictionaries.
class SpacesZoneCopyTest < PhComposerTestCase
  include SpaceFixtures

  API = PhComposer::API
  MAKE_INDEPENDENT = "ph_composer.zones.make_independent"

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @living = space_group(110, space_record("L", :number => "1"),
                          [volume_group(111, volume_record("A"), [floor_face(112, rectangle(0, 0, 3, 4),
                                                                             segment_record("A"))])])
    @hall = space_group(120, space_record("H", :number => "2"),
                        [volume_group(121, volume_record("B"), [floor_face(122, rectangle(3, 0, 2, 2),
                                                                           segment_record("B"))]),
                         volume_group(123, volume_record("C", :number => 2), [floor_face(124, rectangle(3, 2, 2, 2),
                                                                                         segment_record("C"))])])
    @zone = zone_group(100, "Z", [@living, @hall])
    @model.entities << @zone
  end

  def copy_zone(persistent_id, natively: false)
    copy = Sketchup::Group.new(persistent_id, @zone.entities)
    Array(@zone.attribute_dictionaries).each do |dictionary|
      dictionary.each { |key, value| copy.set_attribute(dictionary.name, key, value) }
    end
    @session.host_event(:transaction_committed) if natively
    @model.entities << copy
    treat_duplicates_as_existing(@model) unless natively
    copy
  end

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end

  def rows_under(zone)
    API.query(:context => @context, :name => "ph_composer.spaces.all").dig("value", "spaces")
       .select { |row| row.dig("reference", "entity_path").first == zone.persistent_id }
  end

  def ids(rows)
    rows.flat_map do |row|
      [row["id"]] + row.fetch("volumes").flat_map do |volume|
        segments = volume.fetch("floor_segments").map { |segment| segment["id"] }
        [volume["id"], volume.dig("values", "floor_id")] + segments
      end
    end
  end

  def test_making_a_copied_zone_independent_gives_its_spaces_their_own_ids_in_one_step
    before = ids(rows_under(@zone))
    copy = copy_zone(500)
    operations = @model.operations.length
    result = invoke(MAKE_INDEPENDENT, "zone_path" => [500])
    assert_equal %w[completed committed], result.values_at("status", "effect"), result.inspect
    assert_equal operations + 1, @model.operations.length
    assert_equal before, ids(rows_under(@zone))
    copied = rows_under(copy)
    assert_equal 2, copied.length
    assert_empty ids(copied) & before
    assert_equal ids(copied).uniq, ids(copied)
    assert_equal %w[1 2], copied.map { |row| row.dig("values", "number") }
    (rows_under(@zone) + copied).each do |row|
      refute_includes row.fetch("findings").map { |finding| finding["code"] }, "space.duplicate_identity"
    end
    reported = result.fetch("affected").select { |row| row["kind"].start_with?("ph_composer.spaces.") }
    assert_equal 8, reported.length, "2 Spaces, 3 Volumes, 3 Floor Segments"
  end

  # A copied payload follows its sibling Volume and the Zone to their new ids; the original keeps its own.
  def test_copied_payloads_follow_the_copy_and_the_original_keeps_its_own
    extension = register_extension
    payload = { "volume" => "vol_CCCCCCCCCCCC", "zone" => "zon_ZZZZZZZZZZZZ" }
    data = { extension.namespace => extension.envelope(payload) }
    SPACES::SPACE_STORE.write(@hall, SPACES::SPACE_STORE.read(@hall).merge("extension_data" => data))
    copy = copy_zone(500)
    result = invoke(MAKE_INDEPENDENT, "zone_path" => [500])
    assert_equal "completed", result["status"], result.inspect
    copied_hall = rows_under(copy).find { |row| row.dig("values", "number") == "2" }
    expected = { "volume" => copied_hall.dig("volumes", 1, "id"), "zone" => ZONES::ZONE_STORE.read(copy).fetch("id") }
    assert_equal expected, copied_hall.dig("extension_data", extension.namespace, "payload")
    original_hall = rows_under(@zone).find { |row| row.dig("values", "number") == "2" }
    assert_equal payload, original_hall.dig("extension_data", extension.namespace, "payload")
  end

  def test_an_unsupported_payload_inside_the_copy_refuses_the_whole_zone
    record = volume_record("A").merge("extension_data" => { "outside.vendor" => { "schema_version" => 1 } })
    SPACES::VOLUME_STORE.write(@living.entities.to_a.first, record)
    copy = copy_zone(500)
    zone_id = ZONES::ZONE_STORE.read(copy).fetch("id")
    result = invoke(MAKE_INDEPENDENT, "zone_path" => [500])
    assert_equal %w[refused copy.rule_missing], result.values_at("status", "code")
    assert_equal zone_id, ZONES::ZONE_STORE.read(copy).fetch("id")
  end

  # A Space record that does not read, elsewhere in the Model, is not this repair's to refuse.
  def test_an_unreadable_space_outside_the_copy_does_not_block_it
    stray = Sketchup::Group.new(700, Sketchup::Entities.new([]))
    stray.set_attribute(SPACES::SPACE_STORE.dictionary, SPACES::SPACE_STORE.key, "{not json")
    @model.entities << stray
    copy = copy_zone(500)
    result = invoke(MAKE_INDEPENDENT, "zone_path" => [500])
    assert_equal %w[completed committed], result.values_at("status", "effect"), result.inspect
    refute_equal ZONES::ZONE_STORE.read(@zone).fetch("id"), ZONES::ZONE_STORE.read(copy).fetch("id")
  end

  # The same, with a payload whose typed reference resolves through the Spaces inventory.
  def test_an_unreadable_space_outside_the_copy_does_not_block_its_payloads
    extension = register_extension
    data = { extension.namespace => extension.envelope("volume" => "vol_CCCCCCCCCCCC", "zone" => "zon_ZZZZZZZZZZZZ") }
    SPACES::SPACE_STORE.write(@hall, SPACES::SPACE_STORE.read(@hall).merge("extension_data" => data))
    stray = Sketchup::Group.new(700, Sketchup::Entities.new([]))
    stray.set_attribute(SPACES::SPACE_STORE.dictionary, SPACES::SPACE_STORE.key, "{not json")
    @model.entities << stray
    copy_zone(500)
    result = invoke(MAKE_INDEPENDENT, "zone_path" => [500])
    assert_equal %w[completed committed], result.values_at("status", "effect"), result.inspect
  end

  def test_one_undo_takes_back_the_zone_and_its_spaces_together
    copy_zone(500)
    invoke(MAKE_INDEPENDENT, "zone_path" => [500])
    @model.undo
    copy = SPACES::Occurrences.entity_at(@model, [500])
    assert_equal ZONES::ZONE_STORE.read(@zone), ZONES::ZONE_STORE.read(copy)
    assert_equal ids(rows_under(@zone)), ids(rows_under(copy))
  end

  # The Zones copy watcher's follow-up carries the Spaces with it; the Spaces watcher, which hears only
  # Space Groups and components, leaves the copied Zone alone.
  def test_a_native_zone_copy_is_made_independent_with_its_spaces
    copy = copy_zone(500, :natively => true)
    UI.run_timers
    refute_equal ZONES::ZONE_STORE.read(@zone).fetch("id"), ZONES::ZONE_STORE.read(copy).fetch("id")
    assert_empty ids(rows_under(copy)) & ids(rows_under(@zone))
    assert_equal %w[1 2], rows_under(copy).map { |row| row.dig("values", "number") }
  end

  private

  def register_extension
    references = [{ "path" => "$.volume", "target_kind" => SPACES::VOLUME_KIND, "cardinality" => "one" },
                  { "path" => "$.zone", "target_kind" => ZONES::REFERENCE_KIND, "cardinality" => "one" }]
    extension = PhComposer::Records::Extension.new(:namespace => "test.space_zone_copy.links", :schema_version => 1,
                                                   :references => references)
    PhComposer::Registry.install([Module.new do
      define_singleton_method(:install) do |registry|
        registry.feature("test.space_zone_copy", :contract_version => 1, :requires => ["ph_composer.spaces"])
                .extension(extension)
      end
    end])
    extension
  end
end
