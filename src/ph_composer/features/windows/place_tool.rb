# frozen_string_literal: true

require_relative "placement/tool_target"
require_relative "placement/tool_measurements"
require_relative "placement/tool_inference"

module PhComposer
  module Windows
    # Session-owned native gesture client. Only the public units.place action authors the Model.
    class PlaceTool
      ACTION = "#{FEATURE_ID}.units.place"
      DEFAULT_ANCHOR = "sill_center"
      UNEXPECTED = "The Place tool could not complete that. Nothing was written."
      GUIDANCE = "Place Window: click a Zone Face; sill=<length> sets the opening sill; " \
                 "offset=<length> insets the chosen anchor from the nearest outer edge. Escape stops."
      MEASUREMENTS_LABEL = "sill= or offset="

      def initialize(session)
        @session = session
        @measurements = Placement::ToolMeasurements.new
        @inference = Placement::ToolInference.new
        @sequence = 0
        @anchor = DEFAULT_ANCHOR
        @active = false
      end

      def choose(type_id, anchor: DEFAULT_ANCHOR, host: nil)
        raise CodedError.new("session.unknown", "That Model session is closed.") unless @session.valid?

        @context ||= API.connect(:session_id => @session.id)
        @target ||= Placement::ToolTarget.new(@session, @context)
        Units::Anchors.validate!(anchor)
        plan = @target.refresh(type_id)
        @target.check!(host) if host
        @type_id, @anchor, @host = type_id.dup, anchor.dup, DeepCopy.call(host)
        @plan = plan
        @session.model.select_tool(self) unless active?
        show_guidance
        @session.request_refresh
        state
      end

      def state
        DeepCopy.call("active" => active?, "type_id" => @type_id, "anchor" => @anchor, "host" => @host)
      end

      def active?
        @active == true
      end

      def stop
        cancel
        @measurements.clear
        @suspended = false
        if active? && @session.model.valid?
          @session.model.select_tool(nil)
        end
        @active = false
        @session.request_refresh
        state
      end

      def activate
        @active = true
        @suspended = false
        @measurements.clear
        cancel
        show_guidance
        @session.request_refresh
      end

      def deactivate(view)
        @active = false
        cancel
        Sketchup.set_status_text("", SB_VCB_LABEL)
        view.invalidate
        @session.request_refresh
      end

      def suspend(view)
        cancel
        @suspended = true
        view.invalidate
      end

      def resume(view)
        @suspended = false
        show_guidance
        view.invalidate
      end

      def onCancel(reason, view)
        cancel
        stop if reason.to_i.zero?
        view.invalidate
      end

      def onMouseMove(flags, x, y, view)
        @hover = nil
        unless available?
          cancel
          view.invalidate
          return
        end
        cancel if @gesture && (flags.to_i & MK_LBUTTON).zero?
        cancel if @gesture && @gesture.fetch("edit_path") != edit_path
        return unless @target.current?

        @hover = hover(Pick.face_point(view, x, y), view, x, y)
        view.tooltip = @inference.tooltip || GUIDANCE if view.respond_to?(:tooltip=)
        view.invalidate
      rescue StandardError => error
        failure(error, view)
      end

      def onLButtonDown(_flags, x, y, view)
        @gesture = nil
        return unless available?

        @plan = @target.refresh(@type_id)
        chosen = hover(Pick.face_point(view, x, y), view, x, y)
        return unless chosen

        @gesture = { "params" => { "host" => chosen.fetch(:host).reference, "type_id" => @type_id,
                                   "anchor" => @anchor,
                                   "offsets" => Placement::Offsets.from_point(chosen.fetch(:host).geometry,
                                                                              chosen.fetch(:point)) },
                     "revision" => @session.revision, "edit_path" => edit_path }
        @gesture = DeepCopy.call(@gesture)
        view.invalidate
      rescue StandardError => error
        failure(error, view, :notice => true)
      end

      def onLButtonUp(_flags, _x, _y, view)
        gesture = @gesture
        @gesture = nil
        return unless gesture && available? && gesture.fetch("edit_path") == edit_path

        @sequence += 1
        result = API.invoke(:context => @context, :name => ACTION, :params => gesture.fetch("params"),
                            :request => { "sequence" => @sequence, "expected_revision" => gesture.fetch("revision") })
        completed = result.fetch("status") == "completed"
        announce(completed ? "Placed Window." : HostNotice.words(result), completed ? :info : HostNotice.tone(result))
        @hover = nil
        refresh_after_placement if completed
        view.invalidate
      rescue StandardError => error
        failure(error, view, :notice => true)
      end

      def onUserText(text, view)
        return unless available?

        @measurements.set(text)
        @hover = nil
        Sketchup.status_text = "Measurement set. #{GUIDANCE}"
        view.invalidate
      rescue StandardError => error
        failure(error, view, :notice => true)
      end

      def enableVCB?
        true
      end

      def draw(view)
        return unless available? && @target.current? && @hover

        polygon = @hover.fetch(:outline).map { |point| Geom::Point3d.new(*point.map { |value| value / INCH_TO_M }) }
        segments = polygon.each_with_index.flat_map { |point, index| [point, polygon[(index + 1) % polygon.length]] }
        view.drawing_color = Sketchup::Color.new(47, 143, 131)
        view.draw(GL_LINES, segments)
        @inference.draw(view)
      rescue StandardError => error
        failure(error, view)
      end

      def getMenu(menu, *_arguments)
        Commands.install_feature_menus(menu, :contextual => true)
      end

      def detach
        stop
        @type_id, @host, @plan = nil, nil, nil
      end

      private

      def available?
        active? && @session.valid? && !@suspended && Sketchup.active_model.equal?(@session.model)
      end

      def edit_path
        Array(@session.model.active_path).map(&:persistent_id)
      end

      # The picked Face is the host; SketchUp's inference says where on it. An inferred point off the
      # host's plane, such as CAD linework in front of the wall, lands square onto the plane.
      def hover(picked, view, x, y)
        host = @target.resolve(picked, @host)
        unless host
          @inference.clear
          return
        end

        point = picked.fetch(:point)
        metres = @inference.point_m(view, x, y) || [point.x, point.y, point.z].map { |value| value.to_f * INCH_TO_M }
        metres = @measurements.point(host.geometry, metres, @plan, @anchor)
        outline = Placement::Plane.new(host.geometry).map(@plan, :point_m => metres, :anchor => @anchor).outer_polygon_m
        { :host => host, :point => metres, :outline => outline }
      end

      def cancel
        @gesture = nil
        @hover = nil
        @inference.clear
      end

      def show_guidance
        Sketchup.status_text = GUIDANCE
        Sketchup.set_status_text(MEASUREMENTS_LABEL, SB_VCB_LABEL)
      end

      # A refusal also shows in SketchUp's own notification; "Placed Window." repeats with every click.
      def announce(message, tone)
        return HostNotice.show(@session, message, :tone => tone) unless tone == :info

        Sketchup.status_text = message
        @session.notice(message, :tone => tone)
      end

      def refresh_after_placement
        @plan = @target.refresh(@type_id)
      rescue StandardError => error
        # The placement already committed. A failed follow-up read must not claim it wrote nothing.
        Diagnostics.exception("place_tool_refresh", error)
        announce("Placed Window. The Place tool could not refresh; choose the Type again to continue.", :warning)
      end

      def failure(error, view, notice: false)
        pending = notice || !@gesture.nil?
        cancel
        message = failure_words(error, pending)
        if pending
          announce(message, error.is_a?(UserError) ? :warning : :error)
        else
          Sketchup.status_text = message
        end
        view.invalidate
      end

      # A gesture that failed gets the error and incident a user can quote; a hover that fails only logs and
      # keeps the plain line, because it recurs with the pointer.
      def failure_words(error, pending)
        return error.message if error.is_a?(UserError)
        return UNEXPECTED.tap { Diagnostics.exception("place_tool", error) } unless pending

        HostNotice.words("status" => "failed", "message" => UNEXPECTED,
                         "detail" => Outcome.failure_detail(Diagnostics.incident("place_tool", error), error))
      end
    end

    module_function

    def place_tool(session)
      session.feature_state(:windows_place_tool) { PlaceTool.new(session) }
    end
  end
end
