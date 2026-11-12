# frozen_string_literal: true

module PhComposer
  # The shared Colour-by service: a contribution seam beside feature, provider and exporter
  # (context/EXTENSIBILITY.md, "Colour-by modes"). A feature declares a mode in its own `install`:
  #
  #   feature.colour_mode("ph_composer.zones.by_zone", label: "Zone", entity_kind: "zone",
  #                       colours: ColourBy::Palette.ramp) do |read|
  #     Zones::Occurrences.zones(read.model).map do |zone|
  #       ColourBy::Entry.new(entity: zone.entity, transform: zone.transform,
  #                           value: zone.record.fetch("id"), label: zone.record.fetch("name"))
  #     end
  #   end
  #
  # An entry may also carry world-space shapes (`derived`), and a feature may register a readout,
  # viewport text shown with any mode or none (context/EXTENSIBILITY.md, "Colour-by derived geometry"
  # and "Colour-by readouts"; tools/examples/colour_by/ is the example).
  #
  # The service owns registration, the host overlay, the viewport HUD and cache invalidation. A mode
  # owns a pure projection over its own feature's entities. Nothing here knows a face type, a
  # boundary condition or a Zone, and the shared renderer has no branch per mode.
  #
  # Turning a mode on changes no record, writes no material and opens no operation, so it is not a
  # registered action. It is a view command (Declarations::ViewCommand), reached from the native
  # Colour by menu, from the panel and from any client with `view` access, and read back through the
  # registered `ph_composer.colour_by.state` query.
  module ColourBy
    FEATURE_ID = "#{EXTENSION_ID}.colour_by"
    STATE = "#{FEATURE_ID}.state"
    # Host events that can change what a mode would paint. Service also listens for the session's
    # post-commit change publication, since a native commit callback may arrive before the revision
    # advances. A hidden tag need not advance the revision, so `tags_changed` forces a rebuild.
    #
    # `model_activated` is deliberately absent. A change to a Model while it is inactive reaches the
    # shown Model's observers instead (context/SKETCHUP_HOST_BEHAVIOR.md): the inactive session hears the
    # change as a revision advance alone, and its drawing rebuilds on the next invalidating event it hears.
    INVALIDATING_EVENTS = %i[transaction_committed transaction_undone transaction_redone active_path_changed
                             rendering_options_changed].freeze

    STATE_RESULT = {
      "type" => "object",
      "required" => %w[mode modes rows filter_paths readouts],
      "properties" => {
        "mode" => { "type" => %w[string null], "description" => "The active mode's name, or null when off." },
        "label" => { "type" => %w[string null] },
        "entity_kind" => { "type" => %w[string null] },
        "filter_paths" => {
          "type" => %w[array null],
          "description" => "Occurrence paths to colour; null colours all, and an empty array mutes all.",
          "items" => { "type" => "array", "minItems" => 1,
                       "items" => { "type" => "integer", "minimum" => 1 } }
        },
        "modes" => { "type" => "array", "items" => { "type" => "object" },
                     "description" => "Every registered mode: name, label, entity kind and group (null when none)." },
        "rows" => { "type" => "array", "items" => { "type" => "object" },
                    "description" => "The active mode's legend: value, label, colour, count and state, " \
                                     "and figure, the row's summed area or volume in display units, where the " \
                                     "mode gives one." },
        "readouts" => { "type" => "array", "items" => { "type" => "object" },
                        "description" => "Every registered readout: name, label, whether it reads the selection " \
                                         "and whether it is on." }
      }
    }.freeze

    READOUT_PARAMS = {
      "type" => "object", "additionalProperties" => false, "required" => %w[readout on],
      "properties" => {
        "readout" => { "type" => "string", "description" => "The readout's registered name." },
        "on" => { "type" => "boolean", "description" => "Whether to show it, with any mode or none." }
      }
    }.freeze

    FILTER_PARAMS = {
      "type" => "object", "additionalProperties" => false, "required" => ["paths"],
      "properties" => {
        "paths" => STATE_RESULT.fetch("properties").fetch("filter_paths").merge(
          "description" => "Full root-to-entity persistent-ID occurrence paths to colour, including their " \
                           "descendants; null colours all, and an empty array mutes all. Retained while off."
        )
      }
    }.freeze

    ACTIVATE_PARAMS = {
      "type" => "object", "additionalProperties" => false, "required" => ["mode"],
      "properties" => {
        "mode" => { "type" => %w[string null],
                    "description" => "The mode to turn on, or null to turn Colour-by off." }
      }
    }.freeze

    ROW = {
      "type" => "object", "additionalProperties" => false, "required" => %w[value state],
      "properties" => {
        "value" => { "type" => %w[string null], "description" => "The legend row's value; null is unclassified." },
        "state" => { "type" => "string", "enum" => %w[classified incomplete unclassified] }
      }
    }.freeze
    SELECT_ROW_PARAMS = {
      "type" => "object", "additionalProperties" => false, "required" => ["row"],
      "properties" => { "row" => ROW.merge("description" => "The legend row whose entities to select, as the " \
                                                            "active mode's legend lists it.") }
    }.freeze
    SELECT_ROW_RESULT = {
      "type" => "object", "additionalProperties" => false, "required" => ["selected"],
      "properties" => { "selected" => { "type" => "integer" } }
    }.freeze
    # No row shows everything again, which is what leaving "Show only this" means.
    ISOLATE_PARAMS = {
      "type" => "object", "additionalProperties" => false,
      "properties" => { "row" => ROW.merge("description" => "The legend row to show alone; omit it to show every " \
                                                            "row again.") }
    }.freeze

    module_function

    def install(registry)
      feature = registry.feature(FEATURE_ID, :contract_version => Declarations::CONTRACT_VERSION)
      feature.query(STATE, :description => "The active Colour-by mode, every registered mode and the legend.",
                           :refuses => [],
                           :params => { "type" => "object", "additionalProperties" => false, "properties" => {} },
                           :result => STATE_RESULT, :examples => [{}]) do |request|
        state(request.session)
      end
      declare_views(feature)
      feature.snapshot_section("#{FEATURE_ID}.legend", :query => STATE)
      subscribe_to_invalidation(feature)
    end

    # The view commands: the mode switch, the legend's row commands, the occurrence mask and readouts.
    def declare_views(feature)
      feature.view_command("#{FEATURE_ID}.activate",
                           :description => "Turn one Colour-by mode on, or turn Colour-by off.",
                           :refuses => %w[validation.failed],
                           :params => ACTIVATE_PARAMS, :result => STATE_RESULT,
                           :examples => [{ "mode" => nil }]) do |request|
        activate(request.session, request.params.fetch("mode"))
      end
      feature.view_command("#{FEATURE_ID}.select_row",
                           :description => "Select and zoom to the entities one legend row stands for.",
                           :refuses => %w[validation.failed],
                           :params => SELECT_ROW_PARAMS, :result => SELECT_ROW_RESULT,
                           :examples => [{ "row" => { "value" => "Wall", "state" => "classified" } }]) do |request|
        row = request.params.fetch("row")
        { "selected" => self.for(request.session).select_row(row.fetch("value"), row.fetch("state")) }
      end
      feature.view_command("#{FEATURE_ID}.isolate",
                           :description => "Show one legend row on its own, or show every row again.",
                           :refuses => %w[validation.failed],
                           :params => ISOLATE_PARAMS, :result => STATE_RESULT, :examples => [{}]) do |request|
        row = request.params["row"]
        self.for(request.session).isolate(row && [row.fetch("value"), row.fetch("state")])
        state(request.session)
      end
      feature.view_command("#{FEATURE_ID}.filter",
                           :description => "Colour only matching occurrence paths and mute the remaining geometry.",
                           :refuses => [], :params => FILTER_PARAMS, :result => STATE_RESULT,
                           :examples => [{ "paths" => nil }, { "paths" => [] },
                                         { "paths" => [[101, 102]] }]) do |request|
        self.for(request.session).filter(request.params.fetch("paths"))
        state(request.session)
      end
      feature.view_command("#{FEATURE_ID}.readout",
                           :description => "Show or hide one readout's viewport text, with any mode or none.",
                           :refuses => %w[validation.failed], :params => READOUT_PARAMS, :result => STATE_RESULT,
                           :examples => [{ "readout" => "ph_composer.spaces.show", "on" => true }]) do |request|
        self.for(request.session).readout(request.params.fetch("readout"), :on => request.params.fetch("on"))
        state(request.session)
      end
    end

    def subscribe_to_invalidation(feature)
      INVALIDATING_EVENTS.each do |kind|
        feature.on_host_event(kind) { |session| self.for(session).invalidate! }
      end
      feature.on_host_event(:tags_changed) { |session| self.for(session).invalidate!(:force => true) }
      feature.on_host_event(:section_plane_changed) { |session| self.for(session).invalidate!(:force => true) }
      feature.on_host_event(:selection_changed) { |session| self.for(session).selection_changed }
      # The host can create a session before its file has loaded (Sessions), so an opened file draws again.
      %i[session_created model_opened].each do |kind|
        feature.on_host_event(kind) { |session| self.for(session).open_session }
      end
    end
    private_class_method :declare_views, :subscribe_to_invalidation

    # This Model's Colour-by state, created on first reach. No mode draws until one is turned on.
    def for(session)
      session.feature_state(:colour_by) { Service.new(session) }
    end

    # The panel's route to the mode switch, and the answer it renders the legend from. A name the
    # registry does not hold refuses through the service, naming what was asked for.
    def activate(session, name)
      service = self.for(session)
      name.nil? ? service.deactivate : service.activate(name)
      state(session)
    end

    def state(session)
      service = self.for(session)
      service.legend.merge("modes" => modes, "readouts" => readouts(service))
    end

    # Every registered readout, in registration order, and whether this Model shows it.
    def readouts(service)
      Registry.current.colour_readouts.values.map do |readout|
        { "name" => readout.name, "label" => readout.label, "selection" => readout.selection,
          "on" => service.readouts_on.include?(readout.name) }
      end
    end

    # Every registered mode, in registration order: what a menu or a panel offers.
    def modes
      Registry.current.colour_modes.values.map do |mode|
        { "name" => mode.name, "label" => mode.label, "entity_kind" => mode.entity_kind, "group" => mode.group }
      end
    end

    # The mode the user last chose, so a mode turned on is the one their palette last touched
    # Colour-by itself is off at rest.
    def remembered_mode
      name = Preferences.colour_by_mode
      registered?(name) ? name : nil
    end

    def registered?(name)
      !name.nil? && Registry.current.colour_modes.key?(name)
    end
  end
end
