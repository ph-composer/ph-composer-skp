# frozen_string_literal: true

require_relative "client"
require_relative "thermal_bridge_reference_model"
require_relative "thermal_bridge_schedule_walkthrough"

# The Thermal bridges Colour-by mode on the reference model ThermalBridgeReferenceModel.build makes, and its draw
# cost on ThermalBridgeMeasurement's Model. The mode is turned on from the native Colour by menu; these calls set
# up and read back. Run each line in its own bridge call:
#   ThermalBridgeColourByWalkthrough.assign    the hand calculation's five runs, and Parapet on Zone W's roof
#   ThermalBridgeColourByWalkthrough.report    the mode, its legend as the panel and the HUD show it, its batches
#   ThermalBridgeColourByWalkthrough.hide_tag  Zone B's Balcony Edge on a tag, then the tag hidden
#   ThermalBridgeColourByWalkthrough.hide_ancestor
#                                              the turned wrapper holding Zone W hidden
#   ThermalBridgeColourByWalkthrough.show_all  both shown again
#   ThermalBridgeColourByWalkthrough.locate("Parapet")
#                                              the legend row's select and frame, as the panel's Locate sends it
#   ThermalBridgeColourByWalkthrough.only("Slab edge")
#                                              Show only this; `only(nil)` shows every row again
#   ThermalBridgeColourByWalkthrough.cost      rebuild, Ruby draw and forced-redraw milliseconds, mode on and off
# Hiding and showing are development setup outside the product API, as a user's Tags panel would do them.
module ThermalBridgeColourByWalkthrough
  MODE = "ph_composer.thermal_bridges.by_type"
  TAG = "TB walkthrough"

  module_function

  def assign
    written = ThermalBridgeScheduleWalkthrough.assign_reference
    nested = ThermalBridgeScheduleWalkthrough.assign("Parapet", "zone_w_roof").values_at("status", "effect")
    { "writes" => written + [nested], "report" => report }
  end

  def report
    legend = PhComposer::API.query(:context => client.context, :name => "ph_composer.colour_by.state",
                                   :params => {}).fetch("value")
    {
      "mode" => legend.fetch("mode"), "label" => legend["label"], "entity_kind" => legend["entity_kind"],
      "rows" => legend.fetch("rows").map { |row| row.values_at("label", "count", "figure", "state", "colour") },
      "hud" => hud_lines, "stroke" => service.mode&.stroke,
      "line_points" => service.lines.transform_keys(&:inspect).transform_values(&:length),
      "fills" => service.fills.values.sum(&:length), "rebuilds" => service.rebuilds
    }
  end

  # What the overlay writes in the HUD, drawn into a recording view rather than read off the screen.
  def hud_lines
    overlay = Sketchup.active_model.overlays.find { |item| item.overlay_id.end_with?("colour_by") }
    return [] unless overlay

    recorder = Recorder.new(Sketchup.active_model.active_view)
    overlay.draw(recorder)
    recorder.texts
  end

  def hide_tag
    model = Sketchup.active_model
    tag = model.layers[TAG] || model.layers.add(TAG)
    edge = edges("zone_b_balcony").first
    model.start_operation("Tag the Balcony Edge", true)
    edge.layer = tag
    model.commit_operation
    tag.visible = false
    report
  end

  def hide_ancestor
    wrapper.hidden = true
    report
  end

  def show_all
    wrapper.hidden = false
    tag = Sketchup.active_model.layers[TAG]
    tag.visible = true if tag
    report
  end

  def locate(type)
    row = service.rows.find { |item| item.label == type } || raise("No legend row for #{type}.")
    selected = PhComposer::API.view(:context => client.context, :name => "ph_composer.colour_by.select_row",
                                    :params => { "row" => { "value" => row.value, "state" => row.state.to_s } })
    camera = Sketchup.active_model.active_view.camera
    { "outcome" => selected.values_at("status", "value"),
      "selected" => Sketchup.active_model.selection.to_a.map(&:persistent_id).sort,
      "target_m" => camera.target.to_a.map { |inches| (inches * 0.0254).round(3) } }
  end

  def only(type)
    row = type && (service.rows.find { |item| item.label == type } || raise("No legend row for #{type}."))
    params = row ? { "row" => { "value" => row.value, "state" => row.state.to_s } } : {}
    outcome = PhComposer::API.view(:context => client.context, :name => "ph_composer.colour_by.isolate",
                                   :params => params)
    report.merge("outcome" => outcome.values_at("status", "code"))
  end

  # Median and worst milliseconds over `samples`: a forced rebuild, the overlay's Ruby `draw`, and a forced
  # redraw (`View#refresh`) with the mode on and then off, paired by sample as the overlay spike measured.
  def cost(samples: 30)
    view = Sketchup.active_model.active_view
    service.activate(MODE, :remember => false) unless service.mode_name == MODE
    overlay = Sketchup.active_model.overlays.find { |item| item.overlay_id.end_with?("colour_by") }
    rebuilds = Array.new(samples) { timed { service.invalidate!(:force => true) } }
    draws = Array.new(samples) { timed { overlay.draw(view) } }
    on = Array.new(samples) { timed { view.refresh } }
    service.deactivate
    off = Array.new(samples) { timed { view.refresh } }
    { "assigned_edges" => service_edges, "rebuild_ms" => summary(rebuilds), "ruby_draw_ms" => summary(draws),
      "refresh_on_ms" => summary(on), "refresh_off_ms" => summary(off),
      "added_ms" => summary(on.zip(off).map { |with, without| with - without }) }
  end

  def service_edges
    PhComposer::ThermalBridges::Scan.walk(Sketchup.active_model).first.length
  end

  def summary(values)
    sorted = values.sort
    { "median" => sorted[sorted.length / 2].round(3), "max" => sorted.last.round(3) }
  end

  def timed
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000.0
  end

  def edges(name)
    model = Sketchup.active_model
    ThermalBridgeReferenceModel.paths.fetch(name).map { |path| ThermalBridgeReferenceModel.resolve(model, path).last }
  end

  def wrapper
    Sketchup.active_model.entities.grep(Sketchup::Group).find { |group| group.name == "Turned wrapper" }
  end

  def service
    PhComposer::ColourBy.for(PhComposer::Sessions.current)
  end

  def client
    @client ||= AuthoringExample::Client.new
  end

  # A view that records the HUD's text, drops drawing state, and answers geometry questions from the real one.
  class Recorder
    attr_reader :texts

    def initialize(view)
      @view = view
      @texts = []
    end

    def draw_text(_point, text, _options = {})
      @texts << text
    end

    def draw(*); end

    def draw2d(*); end

    def method_missing(name, *args, &block)
      return nil if name.to_s.end_with?("=")

      @view.respond_to?(name) ? @view.public_send(name, *args, &block) : super
    end

    def respond_to_missing?(name, include_private = false)
      @view.respond_to?(name) || super
    end
  end
end
