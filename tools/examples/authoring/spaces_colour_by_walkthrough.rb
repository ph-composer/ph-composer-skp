# frozen_string_literal: true

# Panel-closed example for the Spaces Colour-by modes and readouts, on any Model with Spaces:
#   SpacesColourByWalkthrough.run
# Turns each Spaces mode on through the public view command and reads its legend back from
# `ph_composer.colour_by.state`, then shows Show Spaces with every optional line and the selection
# totals, and puts the mode and readouts back. None of it writes to the Model, so it leaves no Undo step; the
# result says whether the revision moved.
module SpacesColourByWalkthrough
  API = PhComposer::API
  MODES = %w[by_space by_ventilation by_weighting_factor by_height].map { |mode| "ph_composer.spaces.#{mode}" }
  READOUTS = %w[ph_composer.spaces.show ph_composer.spaces.selection_totals].freeze

  module_function

  def run(session_id: nil)
    session_id ||= API.discover.fetch("sessions").find { |row| row.fetch("active") }&.fetch("id")
    raise ArgumentError, "No open Model session." unless session_id

    context = API.connect(:session_id => session_id)
    before = state(context).fetch("revision")
    legends = MODES.to_h do |mode|
      legend = view(context, "ph_composer.colour_by.activate", "mode" => mode)
      [mode, legend.fetch("rows").map { |row| row.slice("label", "count", "figure", "state") }]
    end
    found_on = state(context).dig("value", "readouts").select { |row| row.fetch("on") }.map { |row| row.fetch("name") }
    READOUTS.each { |name| view(context, "ph_composer.colour_by.readout", "readout" => name, "on" => true) }
    options = view(context, "ph_composer.spaces.labels.set_options",
                   "weighted_area" => true, "net_volume" => true, "airflows" => true)
    # Another feature's readout may be on too; only the Spaces readouts are this walkthrough's to check.
    shown = state(context).dig("value", "readouts").select { |row| row.fetch("on") && READOUTS.include?(row["name"]) }
                          .map { |row| row.fetch("name") }
    READOUTS.each do |name|
      view(context, "ph_composer.colour_by.readout", "readout" => name, "on" => found_on.include?(name))
    end
    view(context, "ph_composer.colour_by.activate", "mode" => nil)
    after = state(context).fetch("revision")
    { "legends" => legends, "readouts_shown" => shown, "label_options" => options,
      "passed" => legends.values.all? { |rows| !rows.empty? } && shown == READOUTS && before == after,
      "revision_moved" => before != after }
  end

  def view(context, name, params)
    result = API.view(:context => context, :name => name, :params => params)
    raise "#{name}: #{result.fetch('message')}" unless result.fetch("status") == "completed"

    result.fetch("value")
  end

  def state(context)
    API.query(:context => context, :name => "ph_composer.colour_by.state")
  end
end
