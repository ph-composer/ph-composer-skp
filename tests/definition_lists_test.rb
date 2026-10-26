# frozen_string_literal: true

require_relative "test_helper"

# The definition lists' shared paging, projection and unreadable report (shell/definition_lists.rb),
# through two features' public reads.
class DefinitionListsTest < PhComposerTestCase
  API = PhComposer::API
  MATERIALS = "ph_composer.assemblies.materials"
  TYPES = "ph_composer.thermal_bridges.types"

  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?("ph_composer.thermal_bridges")
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
  end

  def test_fields_keep_the_identity_and_only_the_fields_asked
    create(TYPES, "name" => "Parapet")
    row = query("#{TYPES}.list", "fields" => %w[export_ready]).fetch("records").first
    assert_equal %w[export_ready id kind schema_version], row.keys.sort
  end

  def test_without_fields_a_row_is_the_row_the_all_read_gives
    create(MATERIALS, "name" => "Mineral wool")
    assert_equal query("#{MATERIALS}.all").fetch("records"), query("#{MATERIALS}.list").fetch("records")
  end

  # The `.all` row schema is closed and checked against every real row at dispatch, so a `fields` enum
  # equal to its properties less the identity can ask for every key a row carries and no other.
  def test_every_definition_list_offers_each_key_its_whole_row_carries
    registry = PhComposer::Registry.current
    identity = PhComposer::DefinitionLists::IDENTITY
    lists = registry.queries.values.select do |query|
      query.result.dig("properties", "records", "items", "required") == identity
    end
    names = lists.map(&:name)
    assert_includes names, "#{MATERIALS}.list"
    assert_includes names, "ph_composer.windows.types.list"
    assert_includes names, "#{TYPES}.list"
    lists.each do |list|
      all = registry.queries.fetch(list.name.sub(/\.list\z/, ".all"))
      keys = all.result.dig("properties", "records", "items", "properties").keys
      assert_equal (keys - identity).sort,
                   list.params.dig("properties", "fields", "items", "enum").sort, list.name
    end
  end

  def test_a_field_the_row_does_not_carry_is_refused
    result = API.query(:context => @context, :name => "#{MATERIALS}.list", :params => { "fields" => ["nope"] })
    assert_equal %w[refused params.invalid], result.values_at("status", "code")
  end

  def test_a_row_larger_than_a_page_comes_alone_and_fields_read_every_row_in_one_page
    ids = %w[Brick Stone Timber].map { |name| create(MATERIALS, { "name" => name }, "notes" => "n" * 20_000) }
    pages = walk("#{MATERIALS}.list")
    assert_equal [1, 1, 1], pages.map { |page| page.fetch("records").length }
    assert_equal ids.sort, pages.flat_map { |page| page.fetch("records").map { |row| row.fetch("id") } }

    page = query("#{MATERIALS}.list", "fields" => %w[values])
    assert_nil page.fetch("next_cursor")
    assert_equal ids.sort, page.fetch("records").map { |row| row.fetch("id") }
  end

  def test_an_unreadable_record_is_reported_beside_the_page_and_counted
    readable = create(TYPES, "name" => "Readable")
    damaged = create(TYPES, "name" => "Damaged")
    kind = PhComposer::ThermalBridges::Type::KIND
    stored = PhComposer::Records::Engine.new(@model, PhComposer::Registry.current.catalog).find(kind.id, damaged)
    kind.store.write(@model, stored.merge("schema_version" => 99))
    page = query("#{TYPES}.list", "fields" => %w[values])
    assert_equal [readable], page.fetch("records").map { |row| row.fetch("id") }
    assert_equal [damaged], page.fetch("unreadable").map { |row| row.fetch("id") }
    assert_equal 2, page.fetch("total")
  end

  private

  def create(owner, values, user_data = nil)
    params = { "values" => values }
    params["user_data"] = user_data if user_data
    @sequence += 1
    result = API.invoke(:context => @context, :name => "#{owner}.create", :params => params,
                        :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
    assert_equal "committed", result["effect"], result.inspect
    result.fetch("value").fetch("id")
  end

  def query(name, params = {})
    result = API.query(:context => @context, :name => name, :params => params)
    assert_equal "completed", result["status"], result.inspect
    result.fetch("value")
  end

  def walk(name)
    pages = [query(name)]
    pages << query(name, "cursor" => pages.last.fetch("next_cursor")) while pages.last.fetch("next_cursor")
    pages
  end
end
