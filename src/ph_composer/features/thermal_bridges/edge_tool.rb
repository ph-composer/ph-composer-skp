# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    # The edge tool: the pointer route to `edges.assign`, armed with one Thermal Bridge Type and quantity
    # (context/EXTENSIBILITY.md, "Viewport tools"). Select then Assign stays the primary route
    # (context/TECH_STACK.md, "Rules for later features"); this one is kept because piping and ducting reuse
    # its shape. It calls `edges.assign` through the public interface like any other client, with its own
    # caller handle and sequence numbers, and opens no operation of its own: an abandoned gesture writes
    # nothing, and one completed gesture is one invoke and one Undo step.
    #
    # What a pick means is read from the pick's own path, never a Model walk: Zones' containment of that path,
    # kept per path until the revision or the open context changes, and the Edge's own record. An Edge no
    # Zone holds, or one a write cannot reach, refuses the whole pending gesture with the reason.
    #
    # The type, the quantity and the revision belong to the gesture, frozen at button-down, so a type chosen
    # mid-drag cannot change what the drag writes.
    class EdgeTool
      ASSIGN = "#{FEATURE_ID}.edges.assign"
      CONTAINMENT = "ph_composer.zones.containment"
      TYPES = "#{FEATURE_ID}.types.list"
      # Pixels: heavier than the Colour-by mode's assigned Edges (ColourModes::STROKE), so what the pointer is
      # over and what the drag has taken read on top of them.
      WIDTH = 8
      HOVER_ALPHA = 140
      COLLECTED_ALPHA = 255
      # The drawing highlight's red, for an Edge under the pointer the tool would refuse.
      REFUSED_COLOUR = [184, 59, 59].freeze
      REASONS = { "outside_zone" => "it is not inside a Zone", "not_found" => "it could not be found in the Model",
                  "not_a_drawing_element" => "it is not a drawing element",
                  "cutting_instance" => "a cutting component holds it",
                  "nested_container" => "a Group or component inside its Zone holds it" }.freeze
      CANCELLED = "The edge tool gesture was cancelled. Nothing was written."
      MISSING_TYPE = "That Thermal Bridge Type no longer exists. Choose another to assign by clicking."

      attr_reader :thermal_bridge_type_id, :quantity

      def initialize(session)
        @session = session
        @thermal_bridge_type_id = nil
        @quantity = Assignment::DEFAULT_QUANTITY
        @type = nil
        @sequence = 0
        @rows = {}
        @collected = nil
        @pressed = false
        @colour_by = ColourBy::Lease.new(session)
      end

      # Arms the tool with a type and quantity and gives it the viewport, turning on Colour by thermal bridge
      # type until it ends (ColourBy::Lease). A choice while the tool runs re-arms it for the next gesture and
      # leaves the one in flight alone.
      def choose(thermal_bridge_type_id, quantity: Assignment::DEFAULT_QUANTITY)
        type = read_type(thermal_bridge_type_id)
        @thermal_bridge_type_id = thermal_bridge_type_id
        @quantity = quantity
        @type = type
        model = @session.model
        model.select_tool(self) if !active? && model.respond_to?(:select_tool)
        @colour_by.take(ColourModes::BY_TYPE)
        show_instructions
        @session.request_refresh
        self
      end

      # Only this tool: a stop arriving after another tool replaced it leaves that tool running.
      def stop
        return self unless active?

        model = @session.model
        model.select_tool(nil) if model.respond_to?(:select_tool)
        self
      end

      def active?
        @active == true
      end

      def state
        { "active" => active?, "thermal_bridge_type_id" => @thermal_bridge_type_id, "quantity" => @quantity }
      end

      # Sketchup::Tool. The host calls these; nothing else does.

      def activate
        @active = true
        reset_gesture
        @hover = nil
        show_instructions
        @session.request_refresh
      end

      def deactivate(view)
        @active = false
        cancel_gesture
        @hover = nil
        @colour_by.release
        view.invalidate if view.respond_to?(:invalidate)
        @session.request_refresh
      end

      # Escape ends the tool with its pending gesture; any other cancel takes only the gesture.
      def onCancel(reason, _view)
        cancel_gesture
        stop if reason.to_i.zero?
      end

      def suspend(view)
        cancel_gesture
        view.invalidate if view.respond_to?(:invalidate)
      end

      def resume(view)
        view.invalidate if view.respond_to?(:invalidate)
      end

      def onMouseMove(flags, x, y, view)
        path = Pick.edge_path(view, x, y)
        # A move without the button down after a press means the host lost the release.
        cancel_gesture if collecting? && (flags.to_i & MK_LBUTTON).zero?
        if collecting?
          collect(path)
        else
          current
          @hover = path && [path, target(path)]
          view.tooltip = tooltip(@hover) if view.respond_to?(:tooltip=)
        end
        view.invalidate if view.respond_to?(:invalidate)
      rescue StandardError => error
        report_exception(error, view)
      end

      def onLButtonDown(_flags, x, y, view)
        @pressed = true
        @gesture_edit_path = edit_path
        @revision = @session.revision
        @type = read_type(@thermal_bridge_type_id)
        return missing_type unless @type

        @gesture = { "thermal_bridge_type_id" => @thermal_bridge_type_id, "quantity" => @quantity,
                     "name" => @type.dig("values", "name"), "colour" => ColourModes.rgb(@type.dig("display", "color")) }
        refresh
        @collected = DragSet.new(:limit => Assignment.gesture_edge_limit)
        collect(Pick.edge_path(view, x, y))
        view.invalidate if view.respond_to?(:invalidate)
      rescue CodedError => error
        reset_gesture
        refuse(error.message)
      rescue StandardError => error
        report_exception(error, view)
      end

      def onLButtonUp(_flags, _x, _y, view)
        unless Sketchup.active_model.equal?(@session.model) && @gesture_edit_path == edit_path
          cancel_gesture
          view.invalidate if view.respond_to?(:invalidate)
          return
        end
        complete
        view.invalidate if view.respond_to?(:invalidate)
      rescue StandardError => error
        report_exception(error, view)
      end

      # What the drag has taken, in the colour of the type it will write; otherwise the Edge under the pointer, in
      # the armed type's colour or red when it would refuse.
      def draw(view)
        if collecting?
          draw_paths(view, @collected.values.map { |item| item[:entities] }, @gesture.fetch("colour"), COLLECTED_ALPHA)
          return
        end
        return if @hover.nil?

        path, (kind, _target) = @hover
        colour = @type && ColourModes.rgb(@type.dig("display", "color"))
        draw_paths(view, [path], kind == :assign ? colour : REFUSED_COLOUR, HOVER_ALPHA)
      rescue StandardError => error
        report_exception(error, view)
      end

      def getMenu(menu, _flags = 0, _x_value = nil, _y_value = nil, view = nil)
        Commands.install_feature_menus(menu, :contextual => true)
      rescue StandardError => error
        report_exception(error, view || @session.model.active_view)
      end

      def getInstructorContentDirectory
        nil
      end

      def detach
        reset_gesture
        @hover = nil
        return unless @active

        @active = false
        model = @session.model
        @colour_by.forget unless model.respond_to?(:valid?) && model.valid?
        model.select_tool(nil) if model.respond_to?(:select_tool)
      end

      private

      def edit_path
        Array(@session.model.active_path).map(&:persistent_id)
      end

      def collecting?
        @pressed && !@collected.nil?
      end

      # A refusal ends the whole pending gesture; pointing at nothing does not.
      def collect(entities)
        return if @collected.nil? || entities.nil?

        kind, target = target(entities)
        if kind == :refuse
          reset_gesture
          refuse(target)
          return
        end
        @collected.add(entities.map(&:persistent_id), { :target => target, :entities => entities })
      end

      # `[:assign, target]` with the `edges.assign` target the Edge's containment and stored record make, or
      # `[:refuse, reason]`.
      def target(entities)
        ids = entities.map(&:persistent_id)
        row = (@rows[ids] ||= query(CONTAINMENT, "paths" => [ids]).fetch("paths").first)
        return [:refuse, row.dig("write_refusal", "message")] if row["write_refusal"]

        record = Assignment::STORE.read(entities.last)
        reference = Assignment::Selection.reference(row, record)
        return [:refuse, unreachable(row.fetch("reason"))] unless reference

        [:assign, { "reference" => reference, "expected_values" => Assignment.values(record) }]
      rescue CodedError => error
        [:refuse, error.message]
      end

      def unreachable(reason)
        "That Edge cannot take a thermal bridge: #{REASONS.fetch(reason, 'no Zone holds it')}."
      end

      def complete
        collected = @collected
        gesture = @gesture
        revision = @revision
        reset_gesture
        return if collected.nil? || collected.empty?

        # Bounded one past the limit, so an over-limit gesture reaches edges.assign, which owns the limit.
        targets = collected.values.map { |item| item[:target] }
        outcome = invoke({ "targets" => targets, "thermal_bridge_type_id" => gesture.fetch("thermal_bridge_type_id"),
                           "quantity" => gesture.fetch("quantity") }, revision)
        count = targets.length
        report(outcome, "Assigned #{gesture.fetch('name')} to #{count == 1 ? '1 Edge' : "#{count} Edges"}.")
      end

      def invoke(params, revision)
        API.invoke(:context => context, :name => ASSIGN, :params => params,
                   :request => { "sequence" => next_sequence, "expected_revision" => revision })
      end

      def report(outcome, done)
        if outcome.fetch("status") == "completed"
          announce(done, :success)
        else
          announce(outcome.fetch("message"), outcome.fetch("status") == "refused" ? :warning : :error)
        end
      end

      # The armed type's row as `types.list` reads it, or nil when it is gone or unreadable.
      def read_type(id)
        query(TYPES, "ids" => [id]).fetch("records").first
      end

      def missing_type
        reset_gesture
        refuse(MISSING_TYPE)
      end

      def query(name, params)
        result = API.query(:context => context, :name => name, :params => params)
        raise CodedError.new(result.fetch("code"), result.fetch("message")) unless result.fetch("status") == "completed"

        result.fetch("value")
      end

      # Containment rows hold for one revision and edit context.
      def refresh
        @rows = {}
        @read_at = read_at
      end

      def current
        refresh unless @read_at == read_at
      end

      def read_at
        [@session.revision, edit_path]
      end

      def context
        @context ||= API.connect(:session_id => @session.id)
      end

      def next_sequence
        @sequence += 1
      end

      def reset_gesture
        @collected = nil
        @pressed = false
        @gesture = nil
      end

      def cancel_gesture
        pending = !@collected.nil?
        reset_gesture
        announce(CANCELLED, :warning) if pending
      end

      # A refusal the tool makes itself says, as an operation's does, that nothing was written.
      def refuse(message)
        announce(message.end_with?(Outcome::NOTHING_WRITTEN) ? message : "#{message} #{Outcome::NOTHING_WRITTEN}",
                 :warning)
      end

      # Results and refusals reach the status bar, which a viewport tool always has, and the panel's notice.
      def announce(message, tone = :info)
        @session.notice(message, :tone => tone)
        Sketchup.status_text = message if Sketchup.respond_to?(:status_text=)
      end

      def show_instructions
        return unless Sketchup.respond_to?(:status_text=)

        name = @type ? @type.dig("values", "name") : "a Thermal Bridge Type"
        Sketchup.status_text = "Assign #{name} by clicking: click or drag across Edges inside a Zone. Escape stops."
      end

      def tooltip(hover)
        return "" if hover.nil?

        _path, (kind, target) = hover
        kind == :assign ? "Assign #{@type ? @type.dig('values', 'name') : 'the type'}" : target
      end

      def draw_paths(view, paths, colour, alpha)
        return if paths.empty? || colour.nil? || !view.respond_to?(:draw)

        segments = paths.flat_map do |entities|
          transform = entities[0...-1].reduce(Geom::Transformation.new) { |sum, entity| sum * entity.transformation }
          edge = entities.last
          [edge.start.position.transform(transform), edge.end.position.transform(transform)]
        end
        view.line_width = WIDTH if view.respond_to?(:line_width=)
        view.line_stipple = "" if view.respond_to?(:line_stipple=)
        view.drawing_color = Sketchup::Color.new(*colour, alpha) if view.respond_to?(:drawing_color=)
        view.draw(GL_LINES, ColourBy::Tessellation.lift(segments, view, 3.0))
        view.line_width = 1 if view.respond_to?(:line_width=)
      end

      def report_exception(error, view)
        pending = !@collected.nil?
        reset_gesture
        @hover = nil
        Diagnostics.exception("edge_tool", error)
        announce("The edge tool could not complete that. #{Outcome::NOTHING_WRITTEN}", :error) if pending
        view.tooltip = "" if view.respond_to?(:tooltip=)
        view.invalidate if view.respond_to?(:invalidate)
      end
    end

    module_function

    # This Model's edge tool, created on first reach and held as session feature state, so its armed type
    # survives the tool ending and a Model closing takes it with it.
    def edge_tool(session)
      session.feature_state(:thermal_bridges_edge_tool) { EdgeTool.new(session) }
    end
  end
end
