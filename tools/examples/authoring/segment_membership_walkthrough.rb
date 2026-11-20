# frozen_string_literal: true

require_relative "client"

# Building Segment membership with the panel closed, through the public API only, in a scratch Model:
#   SegmentMembershipWalkthrough.setup    draws three box Groups and makes House, Annex and Loft Zones
#   SegmentMembershipWalkthrough.run      creates the Annex Segment, moves Annex and Loft into it, moves
#                                         House out of every Segment, deletes Annex with its Zones moved
#                                         to none, refuses to delete the last Segment, moves Loft back
#   SegmentMembershipWalkthrough.verify   reads the Segments and memberships back against EXPECTED; works in
#                                         a fresh process after a reopen
# `run` makes five native Undo steps, named in UNDO_NAMES, newest last. AuthoringExample.undo and .redo
# step through them in separate bridge calls, and `state` shows the memberships between steps.
module SegmentMembershipWalkthrough
  PREFIX = "ph_composer.zones"
  OPTIONS = "#{PREFIX}.options".freeze
  GROUP_PREFIX = "segment_walkthrough_"
  ZONES = %w[House Annex Loft].freeze
  UNDO_NAMES = ["Manage Zone Options", "Edit Selected Zones", "Edit Selected Zones", "Manage Zone Options",
                "Edit Selected Zones"].freeze
  # nil is No Building Segment.
  EXPECTED = { "segments" => ["Building"], "default" => "Building",
               "zones" => { "Annex" => nil, "House" => nil, "Loft" => "Building" } }.freeze

  module_function

  def setup
    model = Sketchup.active_model
    model.start_operation("Segment walkthrough geometry", true)
    ZONES.each_with_index do |name, index|
      AuthoringExample.box(model.entities, "#{GROUP_PREFIX}#{name}", [index * 6000.mm, 0, 0])
    end
    raise "SketchUp refused the walkthrough geometry." unless model.commit_operation

    make_zones
  end

  # One Zone per walkthrough Group, through the public Make Zone; each joins the default Segment.
  def make_zones
    model = Sketchup.active_model
    client = AuthoringExample::Client.new
    ZONES.each do |name|
      group = model.entities.grep(Sketchup::Group).find { |candidate| candidate.name == "#{GROUP_PREFIX}#{name}" }
      result = client.invoke("#{PREFIX}.make", "parent_path" => [], "entity_ids" => [group.persistent_id],
                                               "name" => name)
      raise "Make Zone #{name} failed: #{result['code']}" unless result["effect"] == "committed"
    end
    state
  end

  def run
    client = AuthoringExample::Client.new
    steps = []
    features = PhComposer::API.discover.fetch("features")
    steps << { "step" => "discover", "passed" => features.any? { |row| row["id"] == PREFIX } }
    created = invoke(client, steps, "#{OPTIONS}.create", "collection" => "building_segment",
                                                         "values" => { "name" => "Annex", "colour" => "#5588BB" })
    move(client, steps, %w[Annex Loft], "Annex")
    move(client, steps, ["House"], nil)
    annex_id = created.dig("value", "id")
    removed = invoke(client, steps, "#{OPTIONS}.remove", "collection" => "building_segment", "id" => annex_id,
                                                         "replacement_id" => nil)
    steps << { "step" => "Annex Zones moved to none",
               "passed" => removed.dig("value", "replacement_ids") == { annex_id => nil } }
    last = client.invoke("#{OPTIONS}.remove", "collection" => "building_segment",
                                              "id" => read(client, "#{OPTIONS}.all").fetch("default_segment_id"),
                                              "replacement_id" => nil)
    steps << { "step" => "last Segment refused",
               "passed" => last.values_at("code", "effect") == %w[zone.option_last_segment none] }
    move(client, steps, ["Loft"], "Building")
    steps << { "step" => "read back", "passed" => verify.fetch("passed") }
    { "passed" => steps.all? { |row| row["passed"] }, "steps" => steps }
  end

  # The Segment names, the default's name and each Zone's Segment name (nil for none), as the public reads
  # return them.
  def state
    client = AuthoringExample::Client.new
    options = read(client, "#{OPTIONS}.all")
    names = options.fetch("building_segments").to_h { |row| [row.fetch("id"), row.dig("values", "name")] }
    zones = read(client, "#{PREFIX}.all").fetch("zones").to_h do |zone|
      [zone.dig("values", "name"), names[zone.dig("values", "building_segment_id")]]
    end
    { "segments" => names.values.sort, "default" => names[options.fetch("default_segment_id")],
      "zones" => zones.sort.to_h }
  end

  def verify
    found = state
    { "passed" => found == EXPECTED, "state" => found }
  end

  def move(client, steps, zone_names, segment_name)
    rows = read(client, "#{PREFIX}.all").fetch("zones")
                                        .select { |zone| zone_names.include?(zone.dig("values", "name")) }
    targets = rows.map { |zone| { "reference" => zone.fetch("reference"), "expected_values" => zone.fetch("values") } }
    invoke(client, steps, "#{PREFIX}.update_field", "field" => "building_segment", "value" => segment_name,
                                                    "targets" => targets)
  end

  def read(client, name)
    result = client.query(name)
    raise "#{name} failed: #{result['code']}" unless result["status"] == "completed"

    result.fetch("value")
  end

  def invoke(client, steps, name, params)
    result = client.invoke(name, params)
    steps << { "step" => name, "passed" => result["effect"] == "committed", "code" => result["code"] }
    result
  end
end
