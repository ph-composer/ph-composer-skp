# frozen_string_literal: true

require_relative "client"
require_relative "thermal_bridge_reference_model"

# The schedule with the panel closed, on the reference model ThermalBridgeReferenceModel.build makes.
# Every write is a public action on explicit Edge references; every check reads the schedule back. Run
# each line in its own bridge call:
#   ThermalBridgeScheduleWalkthrough.assign_reference   the five runs of ACCEPTANCE's hand calculation
#   ThermalBridgeScheduleWalkthrough.verify             the schedule against that calculation, each check named
#   ThermalBridgeScheduleWalkthrough.counted_twice      Parapet on the roof Edge at x = 5 m in both Zones
#   ThermalBridgeScheduleWalkthrough.outside_zone       the Balcony record copied onto the line at the Model root
#   ThermalBridgeScheduleWalkthrough.locate_nested      Parapet on Zone W's roof, then runs.locate into it
# `counted_twice` and `locate_nested` each write one Undo step; undo it before `verify` again.
module ThermalBridgeScheduleWalkthrough
  PREFIX = "ph_composer.thermal_bridges"
  DICTIONARY = "ph_composer.thermal_bridge"
  # ACCEPTANCE's runs: name => [length m, quantity, W/K, points].
  EXPECTED = { "Parapet 1" => [14.0, 1, 0.7, 4], "Parapet 2" => [12.0, 1, 0.6, 4],
               "Slab edge 1" => [14.0, 1, 1.68, 4], "Footing 1" => [12.0, 1, -0.24, 4],
               "Balcony 1" => [4.0, 2, 2.0, 2] }.freeze
  TYPES = { "Parapet" => [26.0, 1.3], "Slab edge" => [14.0, 1.68], "Footing" => [12.0, -0.24],
            "Balcony" => [4.0, 2.0] }.freeze
  GROUPS = { "15-Ambient" => 3.3, "16-Perimeter" => 1.68, "17-FS/BC" => -0.24 }.freeze
  TOLERANCE = 0.001

  module_function

  def assign_reference
    { "Parapet" => %w[zone_a_roof zone_b_roof], "Slab edge" => %w[zone_a_ground], "Footing" => %w[zone_b_ground],
      "Balcony" => %w[zone_b_balcony] }.flat_map do |type, names|
      names.map { |name| assign(type, name, :quantity => type == "Balcony" ? 2 : 1).values_at("status", "effect") }
    end
  end

  def verify
    whole = schedule
    runs = whole.fetch("runs").to_h { |row| [row.fetch("display_name"), row] }
    checks = { "five runs" => runs.keys.sort == EXPECTED.keys.sort }
    EXPECTED.each do |name, (length, quantity, loss, points)|
      row = runs[name]
      checks[name] = !row.nil? && near?(row.fetch("length_m"), length) && near?(row.fetch("heat_loss_w_k"), loss) &&
                     row.fetch("quantity") == quantity && row.fetch("points_m").length == points &&
                     row.fetch("findings").empty?
    end
    by_type = whole.dig("totals", "by_type").to_h { |row| [row.fetch("type_name"), row] }
    TYPES.each do |name, (length, loss)|
      row = by_type[name]
      checks["total #{name}"] =
        !row.nil? && near?(row.fetch("length_m"), length) && near?(row.fetch("heat_loss_w_k"), loss)
    end
    by_group = whole.dig("totals", "by_group").to_h { |row| row.values_at("group", "heat_loss_w_k") }
    GROUPS.each { |group, loss| checks["group #{group}"] = near?(by_group.fetch(group), loss) }
    checks["model"] = whole.dig("totals", "run_count") == 5 && near?(whole.dig("totals", "heat_loss_w_k"), 4.74)
    checks["no edge findings"] = whole.fetch("edge_findings").empty? && whole.fetch("unreadable").empty?
    { "pass" => checks.values.all?, "checks" => checks,
      "identifiers" => runs.transform_values { |row| row.fetch("identifier") } }
  end

  def counted_twice
    targets = %w[zone_a_roof_east zone_b_roof_west].flat_map { |name| targets(name) }
    written = client.invoke("#{PREFIX}.edges.assign", "targets" => targets,
                                                      "thermal_bridge_type_id" => type_id("Parapet"))
    runs = schedule.fetch("runs").select { |row| row.fetch("type_name") == "Parapet" }
    { "write" => written.values_at("status", "effect"),
      "runs" => runs.map do |row|
        { "name" => row.fetch("display_name"), "closed" => row.fetch("closed"),
          "length_m" => row.fetch("length_m").round(3),
          "findings" => row.fetch("findings").map { |finding| finding.fetch("code") } }
      end }
  end

  # A native copy carries the dictionary verbatim (T01); copying the Balcony line's dictionary onto the loose
  # line stands in for copying the line out to the Model root. Development setup, outside the product API.
  def outside_zone
    model = Sketchup.active_model
    paths = ThermalBridgeReferenceModel.paths
    balcony = ThermalBridgeReferenceModel.resolve(model, paths.fetch("zone_b_balcony").first).last
    root = ThermalBridgeReferenceModel.resolve(model, paths.fetch("root_edge").first).last
    model.start_operation("Copy Balcony record to the root line", true)
    root.set_attribute(DICTIONARY, "record", balcony.get_attribute(DICTIONARY, "record"))
    model.commit_operation
    whole = schedule
    { "edge_findings" => whole.fetch("edge_findings").map { |finding|
      finding.values_at("code", "path", "blocks_export")
    },
      "runs" => whole.fetch("runs").length }
  end

  def locate_nested
    written = client.invoke("#{PREFIX}.edges.assign", "targets" => targets("zone_w_roof"),
                                                      "thermal_bridge_type_id" => type_id("Parapet"))
    run = schedule.fetch("runs").find { |row| row.dig("zone", "name") == "Zone W" }
    located = client.view("#{PREFIX}.runs.locate", run.fetch("locate"))
    model = Sketchup.active_model
    { "write" => written.values_at("status", "effect"), "run" => run.values_at("display_name", "closed", "length_m"),
      "locate" => located.values_at("status", "value"),
      "active_path" => Array(model.active_path).map(&:persistent_id),
      "selected" => model.selection.to_a.map(&:persistent_id).sort,
      "expected" => run.fetch("edge_paths").map(&:last).sort }
  end

  def assign(type, name, quantity: 1)
    client.invoke("#{PREFIX}.edges.assign", "targets" => targets(name), "thermal_bridge_type_id" => type_id(type),
                                            "quantity" => quantity)
  end

  # Explicit references for the named Edges, from Zones' containment of their native paths.
  def targets(name)
    paths = ThermalBridgeReferenceModel.paths.fetch(name)
    read("ph_composer.zones.containment", "paths" => paths).fetch("paths").map do |row|
      zone = row.fetch("zone") || raise("#{row.fetch('path')} is in no Zone: #{row.fetch('reason')}")
      { "reference" => { "zone_id" => zone.fetch("zone_id"), "zone_path" => zone.fetch("zone_path"),
                         "entity_path" => row.fetch("entity_path"), "entity_id" => nil } }
    end
  end

  def schedule
    read("#{PREFIX}.schedule.all")
  end

  def type_id(name)
    read("#{PREFIX}.types.all").fetch("records").find { |row| row.dig("values", "name") == name }.fetch("id")
  end

  def near?(actual, expected)
    !actual.nil? && (actual - expected).abs <= TOLERANCE
  end

  def read(name, params = {})
    result = client.query(name, params)
    raise "#{name}: #{result['code']} #{result['message']}" unless result["status"] == "completed"

    result.fetch("value")
  end

  def client
    Client.new
  end

  # The authoring client, with the view commands this walkthrough sends.
  class Client < AuthoringExample::Client
    def view(name, params)
      PhComposer::API.view(:context => context, :name => name, :params => params)
    end
  end
end
