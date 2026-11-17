# frozen_string_literal: true

require_relative "../authoring/client"

# Run with the panel closed, through the public API only, in a scratch Model:
#   ClimateSiteWalkthrough.run      reads the site Not set, sets it, then sets each design temperature and the note
#   ClimateSiteWalkthrough.verify   reads both back against EXPECTED; works in a fresh process after a reopen
# Each action is one native Undo step, four in all: "Set Site Location", then "Change Design Temperature"
# three times. AuthoringExample.undo and .redo step through them in separate bridge calls, and `state`
# shows the values between steps.
module ClimateSiteWalkthrough
  PREFIX = "ph_composer.climate"
  SITE_FIELDS = %w[latitude_deg longitude_deg elevation_m climate_zone hours_from_utc].freeze
  DESIGN_FIELDS = %w[heating_99_c cooling_1_c design_temperature_source].freeze
  # A synthetic site and design temperatures; no project data.
  SITE = { "latitude_deg" => 40.6782, "longitude_deg" => -73.9442, "elevation_m" => 10.0, "climate_zone" => 14,
           "hours_from_utc" => -5 }.freeze
  DESIGN = { "heating_99_c" => -12.2, "cooling_1_c" => 31.5,
             "design_temperature_source" => "Walkthrough values, not from a station" }.freeze
  EXPECTED = {
    "site" => SITE.merge("climate_zone_label" => "4", "state" => "set"),
    "design_temperatures" => DESIGN.merge("state" => "set", "warning" => nil),
    "summary" => { "site" => "set", "design_temperatures" => { "state" => "set", "warning" => nil } }
  }.freeze

  module_function

  def run
    client = AuthoringExample::Client.new
    steps = []
    discovered = PhComposer::API.discover.fetch("features").any? { |row| row["id"] == PREFIX }
    steps << { "step" => "discover", "passed" => discovered }
    steps << { "step" => "site not set", "passed" => read(client, "site.get").fetch("state") == "not_set" }
    invoke(client, steps, "site.update", "values" => SITE,
                                         "expected_values" => read(client, "site.get").slice(*SITE_FIELDS))
    DESIGN_FIELDS.each do |field|
      invoke(client, steps, "design_temperatures.update",
             "values" => { field => DESIGN.fetch(field) },
             "expected_values" => { field => read(client, "design_temperatures.get").fetch(field) })
    end
    steps << { "step" => "read back", "passed" => verify.fetch("passed") }
    { "passed" => steps.all? { |row| row["passed"] }, "steps" => steps }
  end

  # The site, the design temperatures and the summary as the public reads return them, in EXPECTED's shape.
  def state
    client = AuthoringExample::Client.new
    { "site" => read(client, "site.get"), "design_temperatures" => read(client, "design_temperatures.get"),
      "summary" => read(client, "summary.get") }
  end

  def verify
    found = state
    { "passed" => found == EXPECTED, "state" => found }
  end

  def read(client, name)
    result = client.query("#{PREFIX}.#{name}")
    raise "#{name} failed: #{result['code']}" unless result["status"] == "completed"

    result.fetch("value")
  end

  def invoke(client, steps, name, params)
    result = client.invoke("#{PREFIX}.#{name}", params)
    steps << { "step" => name, "passed" => result["effect"] == "committed", "code" => result["code"] }
    result
  end
end
