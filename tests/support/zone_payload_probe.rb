# frozen_string_literal: true

# A test-only feature that keeps a payload on each Zone record naming its own catalog records through one `one`
# and one `many` declared reference, built only from the public registration calls a feature that requires Zones
# uses (context/EXTENSIBILITY.md, "Metadata and structured extension data"). It writes the payload through Zones'
# proposal participant, as Programs' Zone assignment does (context/CONTRACTS.md, "Occupancy"), and its delete moves
# every payload naming the deleted item to a replacement in the same proposal, as Programs' deletes do. Nothing here
# is a building record; it exists to prove the engine's reference handling over a `many` slot in a Zone payload.
module ZonePayloadProbe
  R = PhComposer::Records
  ID = "test.zone_payload"
  ITEM_KIND = "#{ID}.item"
  NAMESPACE = "#{ID}.slots"
  CREATE = "#{ID}.create"
  ASSIGN = "#{ID}.assign"
  DELETE = "#{ID}.delete"
  BY_SINGLE = "#{ID}.by_single"
  STAGE = PhComposer::Zones::ExtensionStaging::NAME
  SLOTS = %w[single_id multiple_ids].freeze
  EMPTY = { "single_id" => nil, "multiple_ids" => [] }.freeze
  OBJECT = { "type" => "object" }.freeze
  ID_PATTERN = /\Atpi_[A-Za-z0-9]{12}\z/.freeze

  ITEM = R::RecordKind.new(
    :id => ITEM_KIND, :label => "Probe item", :schema_version => 1, :id_prefix => "tpi",
    :fields => [R::Field.new(:key => "name", :schema => { "type" => "string", "minLength" => 1 }, :required => true)]
  )

  module_function

  # A whole payload: both slots, the single one an item id or null, the list item ids held once each.
  def problems(payload)
    found = []
    found << "the slots are #{SLOTS.join(' and ')}" unless payload.keys.sort == SLOTS.sort
    single = payload["single_id"]
    found << "single_id must be an item id or null" unless single.nil? || ID_PATTERN.match?(single.to_s)
    list = payload["multiple_ids"]
    if !list.is_a?(Array) || !list.all? { |id| ID_PATTERN.match?(id.to_s) }
      found << "multiple_ids must be a list of item ids"
    elsif list.uniq.length != list.length
      found << "multiple_ids holds an id twice"
    end
    found
  end

  EXTENSION = R::Extension.new(
    :namespace => NAMESPACE, :schema_version => 1, :export_relevance => "local_only",
    :references => [{ "path" => "$.single_id", "target_kind" => ITEM_KIND, "cardinality" => "one" },
                    { "path" => "$.multiple_ids", "target_kind" => ITEM_KIND, "cardinality" => "many" }],
    :validate => ->(payload) { problems(payload) }
  )

  REFUSES = (PhComposer::Zones::ExtensionStaging::REFUSES + %w[reference.in_use]).uniq.freeze

  def install(registry)
    feature = registry.feature(ID, :contract_version => 1, :requires => ["ph_composer.zones"])
    feature.record_kind(ITEM)
    feature.extension(EXTENSION)
    feature.action(CREATE, :description => "Create one item.",
                           :params => { "type" => "object", "required" => ["name"],
                                        "properties" => { "name" => { "type" => "string" } } },
                           :result => OBJECT, :refuses => %w[validation.failed], :undo_name => "Create Probe Item",
                           :side_effects => "Creates a record.",
                           :examples => [{ "name" => "Item" }]) do |request, proposal|
      { "id" => request.engine.propose_create(ITEM_KIND, proposal, :values => { "name" => request.params["name"] }) }
    end
    feature.action(ASSIGN, :description => "Stage each named Zone's whole payload through Zones.",
                           :params => { "type" => "object", "required" => ["zones"],
                                        "properties" => { "zones" => { "type" => "array" } } },
                           :result => OBJECT, :refuses => REFUSES, :participants => [STAGE],
                           :undo_name => "Assign Probe Items", :side_effects => "Updates Zone records.",
                           :examples => [{ "zones" => [] }]) do |request, _proposal|
      request.participate(STAGE, "namespace" => NAMESPACE, "zones" => request.params.fetch("zones"))
    end
    feature.action(DELETE, :description => "Delete an item; a replacement takes every Zone payload naming it.",
                           :params => { "type" => "object", "required" => ["id"],
                                        "properties" => { "id" => { "type" => "string" },
                                                          "replacement_id" => { "type" => "string" } } },
                           :result => OBJECT, :refuses => REFUSES, :participants => [STAGE],
                           :undo_name => "Delete Probe Item", :side_effects => "Deletes a record, moving its uses.",
                           :examples => [{ "id" => "tpi_Ab12Cd34Ef56" }]) do |request, proposal|
      id = request.params.fetch("id")
      replacement = request.params["replacement_id"]
      plan = replacement && retarget(request, id, replacement)
      request.engine.propose_delete(ITEM_KIND, id, proposal, :reference_plan => plan)
      { "id" => id }
    end
    feature.colour_mode(BY_SINGLE, :label => "Probe item", :entity_kind => "zone",
                                   :colours => PhComposer::ColourBy::Palette.ramp) { |read| zone_entries(read) }
  end

  # Each Zone occurrence keyed by Zone id from Zones' public read, its entity and world transform resolved from
  # the row's occurrence path by the core walk: the projection names no Zones internals.
  def zone_entries(read)
    read.query("ph_composer.zones.all").fetch("zones").map do |row|
      path = row.dig("reference", "zone_path")
      resolved = PhComposer::OccurrencePath.resolve(read.model, path)
      value = row.fetch("extension_data", {}).dig(NAMESPACE, "payload", "single_id")
      PhComposer::ColourBy::Entry.new(:entity => resolved.instances.last, :transform => resolved.transform,
                                      :value => value, :label => value, :path => path)
    end
  end

  # Every Zone payload naming `from` names `to` instead, staged through Zones; the plan projects those Zones as
  # the proposal leaves them, so the delete's incoming-reference check reads the moved payloads.
  def retarget(request, from, to)
    zones = request.query("ph_composer.zones.all").fetch("zones").filter_map do |row|
      payload = row.fetch("extension_data", {}).dig(NAMESPACE, "payload")
      moved = payload && renamed(payload, from, to)
      { "reference" => row.fetch("reference"), "payload" => moved } if moved
    end
    entries = zones.empty? ? [] : request.participate(STAGE, "namespace" => NAMESPACE, "zones" => zones)
                                         .fetch("zone_entries")
    R::ReferencePlan.new(:entries => entries.map do |entry|
      R::ReferenceEntry.new(:kind => entry.fetch("kind"), :key => entry.fetch("key"), :record => entry.fetch("record"))
    end, :removals => [])
  end

  def renamed(payload, from, to)
    single = payload.fetch("single_id") == from ? to : payload.fetch("single_id")
    multiple = payload.fetch("multiple_ids").map { |id| id == from ? to : id }.uniq
    after = { "single_id" => single, "multiple_ids" => multiple }
    after == payload ? nil : after
  end
end
