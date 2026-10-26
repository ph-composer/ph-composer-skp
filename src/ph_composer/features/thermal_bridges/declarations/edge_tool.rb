# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    # The edge tool's public face: its state, read by the panel's assign bar, the two view commands that arm
    # and stop it, and their native menu items. Neither command changes a record, so neither is an action;
    # each gesture the tool completes is one `edges.assign`, the route's explicit-reference equivalent.
    module EdgeToolRegistration
      PREFIX = "#{FEATURE_ID}.edge_tool".freeze
      CHOOSE_REFUSES = %w[record.unreadable target.not_found validation.failed].freeze
      ARM_LABEL = "Assign by clicking…"
      STOP_LABEL = "Stop assigning by clicking"
      QUANTITY = { "type" => "number", "exclusiveMinimum" => 0 }.freeze
      STATE = Shapes.object({
        "active" => { "type" => "boolean", "description" => "Whether the edge tool has the viewport." },
        "thermal_bridge_type_id" => { "type" => %w[string null],
                                      "description" => "The type the tool assigns, or null before one is chosen." },
        "quantity" => QUANTITY.merge("description" => "How many times each Edge it assigns counts."),
        "gesture_limit" => { "type" => "integer", "minimum" => 0,
                             "description" => "The most Edges one gesture may assign." }
      }).freeze
      CHOOSE_PARAMS = Shapes.object({
        "thermal_bridge_type_id" => Shapes.id(Type::KIND.id_prefix, "The Thermal Bridge Type to assign by clicking."),
        "quantity" => QUANTITY.merge("description" => "How many times each Edge counts; 1 when absent.")
      }, :optional => ["quantity"]).freeze

      module_function

      def install(feature)
        feature.query("#{PREFIX}.state",
                      :description => "The edge tool: whether it has the viewport, and the type and quantity it " \
                                      "assigns.",
                      :refuses => [], :params => Shapes::NONE, :result => STATE, :examples => [{}]) do |request|
          state(request.session)
        end
        feature.snapshot_section(PREFIX, :query => "#{PREFIX}.state")
        install_commands(feature)
        install_menus(feature)
      end

      def install_commands(feature)
        feature.view_command("#{PREFIX}.choose",
                             :description => "Arm the edge tool with a Thermal Bridge Type and quantity and give it " \
                                             "the viewport: each click or drag across Edges is one edges.assign.",
                             :refuses => CHOOSE_REFUSES, :params => CHOOSE_PARAMS, :result => STATE,
                             :preconditions => ["The Thermal Bridge Type exists and is readable."],
                             :side_effects => "Gives the viewport to the edge tool and turns on Colour by " \
                                              "Thermal bridges until it stops; a choice while it runs re-arms it " \
                                              "for the next gesture.",
                             :examples => [{ "thermal_bridge_type_id" => Shapes.example_id(Type::KIND) },
                                           { "thermal_bridge_type_id" => Shapes.example_id(Type::KIND),
                                             "quantity" => 2 }]) do |request|
          id = request.params.fetch("thermal_bridge_type_id")
          request.engine.find(TYPE_KIND, id)
          ThermalBridges.edge_tool(request.session)
                        .choose(id, :quantity => request.params.fetch("quantity", Assignment::DEFAULT_QUANTITY))
          state(request.session)
        end
        feature.view_command("#{PREFIX}.stop",
                             :description => "Give the viewport back to whatever tool the user had.",
                             :refuses => [], :params => Shapes::NONE, :result => STATE,
                             :side_effects => "Abandons a pending gesture and puts back the Colour-by mode from " \
                                              "before the tool, unless another was chosen meanwhile.",
                             :examples => [{}]) do |request|
          ThermalBridges.edge_tool(request.session).stop
          state(request.session)
        end
      end

      # Under the extension's menu, and in the right-click "Thermal bridge" submenu where it already shows, on a
      # selection holding an Edge a write can reach, so it does not join every other right-click.
      def install_menus(feature)
        feature.menu_item("#{PREFIX}.arm_menu", :label => ARM_LABEL, :menu => MenuRegistration::MENU,
                                                :available => ->(read) {
                                                  !type_rows(read).empty? && !MenuRegistration.assignable(read).empty?
                                                }) do |session|
          arm_from_menu(session)
        end
        feature.menu_item("#{PREFIX}.stop_menu", :label => STOP_LABEL, :menu => MenuRegistration::MENU,
                                                 :available => ->(read) {
                                                   ThermalBridges.edge_tool(read.session).active?
                                                 }) do |session|
          ThermalBridges.edge_tool(session).stop
        end
      end

      def state(session)
        ThermalBridges.edge_tool(session).state.merge("gesture_limit" => Assignment.gesture_edge_limit)
      end

      def type_rows(read)
        read.query("#{TypeRegistration::PREFIX}.all").fetch("records")
            .sort_by { |row| [row.dig("values", "name").downcase, row.fetch("id")] }
      end

      # A menu handler is a client: it reads the types and arms the tool through one long-lived context per
      # session, and shows a refusal rather than doing nothing.
      def arm_from_menu(session)
        read = API.query(:context => context(session), :name => "#{TypeRegistration::PREFIX}.all")
        return show_refusal(session, read) unless read.fetch("status") == "completed"

        rows = read.fetch("value").fetch("records").sort_by { |row| row.dig("values", "name").downcase }
        return if rows.empty?

        tool = ThermalBridges.edge_tool(session)
        chosen = rows.find { |row| row.fetch("id") == tool.thermal_bridge_type_id } || rows.first
        names = rows.map { |row| row.dig("values", "name") }
        answer = UI.inputbox(["Thermal Bridge Type", "Quantity"], [chosen.dig("values", "name"), tool.quantity.to_s],
                             [names.join("|"), ""], "Assign by clicking")
        return unless answer

        selected = rows.find { |row| row.dig("values", "name") == answer.first }
        return unless selected

        params = { "thermal_bridge_type_id" => selected.fetch("id"), "quantity" => quantity(answer.last) }
        show_refusal(session, API.view(:context => context(session), :name => "#{PREFIX}.choose", :params => params))
      end

      DECIMAL = /\A[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?\z/

      # The typed quantity as a finite decimal number, or the text as typed so the command refuses it with its
      # own reason.
      def quantity(text)
        typed = text.to_s.strip
        value = typed.match?(DECIMAL) ? Float(typed) : nil
        value&.finite? ? value : typed
      end

      def show_refusal(session, result)
        return result if result.fetch("status") == "completed"

        Sketchup.status_text = result.fetch("message")
        session.notice(result.fetch("message"), :tone => :warning)
        result
      end

      def context(session)
        session.feature_state(:thermal_bridges_menu_context) { API.connect(:session_id => session.id) }
      end
    end
  end
end
