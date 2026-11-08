# frozen_string_literal: true

require_relative "../place_tool"
require_relative "../units/locate"
require_relative "../units/naming"

module PhComposer
  module Windows
    module ViewportRegistration
      PREFIX = "#{FEATURE_ID}.place_tool"
      MENU = "Place Windows"

      module_function

      def install(feature, registry)
        face = DeepCopy.call(registry.record_descriptor("ph_composer.zones.faces.face").occurrence_schema)
        nullable_face = face.merge("type" => %w[object null])
        state = Shapes.object({ "active" => { "type" => "boolean" },
                                "type_id" => { "type" => %w[string null] },
                                "anchor" => { "type" => "string", "enum" => Units::Anchors::ALL },
                                "host" => nullable_face })
        params = Shapes.object({ "type_id" => Shapes.id("wnt", "The Window Type to place."),
                                 "anchor" => UnitRegistration::ANCHOR.merge(
                                   "description" => "#{UnitRegistration::ANCHOR_TEXT} sill_center when absent."
                                 ),
                                 "host" => nullable_face.merge("description" => "A Face to place on, or null to pick " \
                                                                                "one in the viewport.") },
                               :optional => %w[anchor host])
        feature.query("#{PREFIX}.get", :description => "This Model's Place tool choice and active state.",
                                       :refuses => [],
                                       :params => Shapes::NONE, :result => state, :examples => [{}]) do |request|
          Windows.place_tool(request.session).state
        end
        feature.snapshot_section(PREFIX, :query => "#{PREFIX}.get")
        feature.view_command("#{PREFIX}.choose",
                             :description => "Choose a Type and anchor, then start Place.",
                             :refuses => Refuses::PLACE_TOOL_CHOOSE,
                             :params => params, :result => state,
                             :examples => [{ "type_id" => "wnt_Ab12Cd34Ef56" }]) do |request|
          Windows.place_tool(request.session).choose(request.params.fetch("type_id"),
                                                     :anchor => request.params.fetch("anchor",
                                                                                     PlaceTool::DEFAULT_ANCHOR),
                                                     :host => request.params["host"])
        end
        feature.view_command("#{PREFIX}.stop",
                             :description => "Stop Place and abandon its pending gesture.",
                             :refuses => [],
                             :params => Shapes::NONE, :result => state, :examples => [{}]) do |request|
          Windows.place_tool(request.session).stop
        end
        locate(feature)
        menus(feature)
      end

      def locate(feature)
        reference = Units::TARGET.descriptor.occurrence_schema
        feature.view_command("#{FEATURE_ID}.units.locate",
                             :description => "Select and zoom to explicit Window occurrences.",
                             :refuses => %w[record.unreadable target.changed target.wrong_kind validation.failed],
                             :params => Shapes.object({ "units" => Shapes.list(reference).merge(
                               "minItems" => 1, "maxItems" => 500,
                               "description" => "The Window occurrences to select, as units.list references them."
                             ) }),
                             :result => Shapes.object({ "units" => Shapes.list(reference) }),
                             :examples => [{ "units" => [UnitRegistration::EXAMPLE_UNIT] }]) do |request|
          Units::Locate.call(request.model, request.params.fetch("units"))
        end
        selection(feature, reference)
      end

      # Never refuses, so a selection holding no Window reads as none rather than as a failure.
      def selection(feature, reference)
        feature.query("#{FEATURE_ID}.units.selection",
                      :description => "The Window occurrences selected in SketchUp, at the active edit path.",
                      :refuses => [], :params => Shapes::NONE,
                      :result => Shapes.object({ "units" => Shapes.list(reference) }),
                      :response => { "bounded" => false, "prefer" => "#{FEATURE_ID}.units.list" },
                      :examples => [{}]) { |request| { "units" => Units::Naming.selected(request.model) } }
        feature.snapshot_section("#{FEATURE_ID}.units.selected", :query => "#{FEATURE_ID}.units.selection")
      end

      def menus(feature)
        feature.menu_item("#{PREFIX}.menu", :label => "Place Window…", :menu => MENU,
                                            :available => ->(read) {
                                                            !type_rows(read.engine).empty?
                                                          }) { |session| choose_from_menu(session) }
        feature.menu_entries("#{PREFIX}.face_menu", :menu => MENU,
                                                    :available => ->(read) { !selected_face(read).nil? }) do |read|
          host = selected_face(read)
          type_rows(read.engine).map do |row|
            id = row.fetch("id")
            Declarations::MenuEntry.new(:label => "Place #{row.fetch('name')}", :handler => ->(target) {
              invoke_choice(target, { "type_id" => id, "host" => host })
            })
          end
        end
        feature.menu_item("#{PREFIX}.exit_menu", :label => "Stop Place", :menu => MENU,
                                                 :available => ->(read) {
                                                                 Windows.place_tool(read.session).active?
                                                               }) do |session|
          Windows.place_tool(session).stop
        end
      end

      def type_rows(engine)
        Snapshot.readable(engine, Types::KIND).map { |type| type.slice("id", "name") }
      end

      # The Zones selection read, for a menu test or entry provider. Anything but one Face is nil.
      def selected_face(read)
        return unless single_face?(read.model)

        faces = read.query("ph_composer.zones.faces.selection").fetch("faces")
        faces.first if faces.length == 1
      rescue UserError
        nil
      end

      # A menu handler is a client: it reads and chooses through one long-lived context per session.
      def choose_from_menu(session)
        rows = type_choices(session)
        return if rows.nil? || rows.empty?

        choices = [rows.map { |row| row.fetch("name") }.join("|")]
        choice = UI.inputbox(["Window Type"], [rows.first.fetch("name")], choices,
                             "Place Window")
        return unless choice

        selected = rows.find { |row| row.fetch("name") == choice.first }
        return unless selected

        params = { "type_id" => selected.fetch("id") }
        host = selected_host(session)
        params["host"] = host if host
        invoke_choice(session, params)
      end

      # Every readable Type, page by page; nil when a page is refused.
      def type_choices(session)
        rows = []
        params = { "kind" => TYPE_KIND, "fields" => ["name"], "limit" => Pages::MAXIMUM_LIMIT }
        loop do
          page = query(session, "ph_composer.records.list", params)
          return unless page

          page.fetch("records").each { |row| rows << { "id" => row.fetch("id"), "name" => row.dig("values", "name") } }
          return rows unless page.fetch("next_cursor")

          params = params.merge("cursor" => page.fetch("next_cursor"))
        end
      end

      def selected_host(session)
        return unless single_face?(session.model)

        faces = query(session, "ph_composer.zones.faces.selection", {})&.fetch("faces")
        faces.first if faces&.length == 1
      end

      def single_face?(model)
        selected = model.selection.to_a
        selected.length == 1 && selected.first.is_a?(Sketchup::Face)
      end

      def invoke_choice(session, params)
        result = API.view(:context => context(session), :name => "#{PREFIX}.choose", :params => params)
        show_refusal(session, result)
        result
      end

      # A refused read is shown, as a refused choice is, rather than silently doing nothing.
      def query(session, name, params)
        result = API.query(:context => context(session), :name => name, :params => params)
        return result.fetch("value") if result.fetch("status") == "completed"

        show_refusal(session, result)
        nil
      end

      def show_refusal(session, result)
        return if result.fetch("status") == "completed"

        Sketchup.status_text = result.fetch("message")
        session.notice(result.fetch("message"), :tone => :warning)
      end

      def context(session)
        session.feature_state(:windows_menu_context) { API.connect(:session_id => session.id) }
      end
    end
  end
end
