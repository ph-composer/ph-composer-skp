# frozen_string_literal: true

require_relative "../authoring/client"

# Run with the panel closed, through the public API only, in a scratch Model:
#   ProgramRecordsWalkthrough.run      reads PH-Composer's defaults unwritten, then authors through each record kind
#   ProgramRecordsWalkthrough.verify   reads the result back against what run left; works in a fresh process after a
#                                      save and reopen
# Each action is one native Undo step (UNDO_NAMES). AuthoringExample.undo and .redo step through them in separate
# bridge calls, and `state` shows the records between steps. Every value is synthetic.
module ProgramRecordsWalkthrough
  PREFIX = "ph_composer.programs"
  OFFICE_HOURS = { "name" => "Walkthrough office hours", "type" => "fractional", "start_h" => 7, "end_h" => 18,
                   "fraction_on" => 1.0, "fraction_off" => 0.0, "days_per_week" => 5, "weeks_per_year" => 50 }.freeze
  OFFICE = "Walkthrough office"
  DEVICE = { "display_name" => "Walkthrough server rack", "energy_demand" => 150.0 }.freeze
  UNDO_NAMES = ["Create Schedule", "Create Program", "Edit Program", "Add Device", "Change Programs Defaults",
                "Delete Program", "Reset to PH-Composer Default"].freeze

  module_function

  def run
    client = AuthoringExample::Client.new
    steps = []
    discovered = PhComposer::API.discover.fetch("features").any? { |row| row["id"] == PREFIX }
    steps << { "step" => "discover", "passed" => discovered }
    defaults = read(client, "settings.get")
    residential = defaults.fetch("default_program_id")
    unwritten = rows(client, "programs").find { |row| row["id"] == residential }
    steps << { "step" => "defaults read unwritten", "passed" => unwritten && unwritten["stored"] == false }
    hours = invoke(client, steps, "schedules.create", "values" => OFFICE_HOURS).fetch("id")
    office = invoke(client, steps, "programs.create",
                    "values" => { "name" => OFFICE, "people" => people(unwritten, hours) }).fetch("id")
    lighting = unwritten.dig("values", "lighting")
    edited = lighting.merge("high_efficacy_fraction" => 0.9)
    invoke(client, steps, "programs.update", "id" => residential, "values" => { "lighting" => edited },
                                             "expected_values" => { "lighting" => lighting })
    invoke(client, steps, "equipment_sets.add_device", "id" => defaults.fetch("default_equipment_set_id"),
                                                       "type" => "custom_annual_mel", "values" => DEVICE)
    invoke(client, steps, "settings.update", "values" => { "default_program_id" => office },
                                             "expected_values" => { "default_program_id" => residential })
    invoke(client, steps, "programs.delete", "id" => residential)
    invoke(client, steps, "reset_default", "kind" => "program")
    steps << { "step" => "read back", "passed" => verify.fetch("passed") }
    { "passed" => steps.all? { |row| row["passed"] }, "steps" => steps }
  end

  # The office Program's People: a fixed density on the walkthrough's hours, the rest as the default has it.
  def people(default, schedule_id)
    default.dig("values", "people").merge("rule" => nil, "people_per_area" => 0.05,
                                          "occupancy_schedule_id" => schedule_id)
  end

  # What the public reads return, in the shape `verify` compares.
  def state
    client = AuthoringExample::Client.new
    programs = rows(client, "programs")
    sets = rows(client, "equipment_sets")
    { "defaults" => read(client, "settings.get"),
      "programs" => programs.map { |row| [row.dig("values", "name"), row["stored"], row["default"]] },
      "lighting" => programs.map { |row| row.dig("values", "lighting", "high_efficacy_fraction") },
      "schedules" => rows(client, "schedules").map { |row| [row.dig("values", "name"), row["use_count"]] },
      "devices" => sets.map { |row| row.dig("values", "devices").map { |device| device["display_name"] } } }
  end

  # After run: the office is the default, the residential default is back as its definition has it and stored,
  # the default Set carries the added device and the office hours drive the office's People.
  def verify
    found = state
    programs = found.fetch("programs")
    passed = programs.include?([OFFICE, true, true]) && programs.include?(["Residential default", true, false]) &&
             found.fetch("lighting").compact.uniq == [1.0] &&
             found.fetch("schedules").include?([OFFICE_HOURS.fetch("name"), 1]) &&
             found.fetch("devices").flatten.include?(DEVICE.fetch("display_name"))
    { "passed" => passed, "state" => found }
  end

  def rows(client, collection)
    read(client, "#{collection}.all").fetch("records")
  end

  def read(client, name)
    result = client.query("#{PREFIX}.#{name}")
    raise "#{name} failed: #{result['code']}" unless result["status"] == "completed"

    result.fetch("value")
  end

  def invoke(client, steps, name, params)
    result = client.invoke("#{PREFIX}.#{name}", params)
    passed = result["effect"] == "committed"
    steps << { "step" => name, "passed" => passed, "code" => result["code"] }
    raise "#{name} failed: #{result['code']} #{result['message']}" unless passed

    result.fetch("value")
  end
end
