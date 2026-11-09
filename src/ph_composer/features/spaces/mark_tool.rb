# frozen_string_literal: true

module PhComposer
  module Spaces
    # The Mark floor tool: the viewport half of marking Floor Segments (context/EXTENSIBILITY.md, "Viewport
    # tools"). It calls `floors.mark` and `volumes.create` through the public interface like any other client,
    # with its own caller handle and sequence numbers, and opens no operation of its own: an abandoned
    # gesture writes nothing, and one completed gesture is one invoke and one Undo step.
    #
    # What a pick means: a Face directly inside a Volume is marked with the weighting factor; a Face at a
    # Space's root becomes that Space's next Volume; a Face loose in the open context and in no Space is
    # offered Create Space, and nothing is written on the click; a classified Zone Face, or a Face inside a
    # closed Group, refuses with the reason. One gesture works in one place, so a drag mixing those refuses whole.
    #
    # The weighting factor is this Model's choice, set when the tool starts; a gesture freezes it, and the
    # revision, at button-down, so a factor chosen mid-drag cannot change what the drag writes.
    #
    # What a pick means is MarkPlacement's, read from the pick's own path, never a Model walk.
    class MarkTool
      MARK = "#{FEATURE_ID}.floors.mark"
      ADD_VOLUME = "#{FEATURE_ID}.volumes.create"
      HOVER_COLOUR = [184, 59, 59].freeze
      COLLECTED_COLOUR = [47, 143, 131].freeze
      FILL_ALPHA = 90
      OUTLINE_ALPHA = 230
      MIXED = "One gesture marks Faces in one place: inside Volumes, or at one Space's root. Nothing was written."
      CANCELLED = "The Mark floor gesture was cancelled. Nothing was written."
      OFFER = "That Face is in no Space. Right-click it and choose Create Space to make one from it."

      attr_reader :weighting_factor, :offered

      def initialize(session)
        @session = session
        @weighting_factor = 1.0
        @sequence = 0
        @collected = nil
        @pressed = false
        @offered = []
        @colour_by = ColourBy::Lease.new(session)
      end

      # Sets the factor and starts the tool, turning on Colour by weighting factor until the tool ends
      # (ColourBy::Lease). The mode follows the tool change, so a tool giving back the mode it took cannot
      # take this one with it.
      def start(weighting_factor)
        @weighting_factor = Float(weighting_factor)
        model = @session.model
        model.select_tool(self) if model.respond_to?(:select_tool)
        @colour_by.take(ColourModes::BY_WEIGHTING_FACTOR)
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
        { "active" => active?, "weighting_factor" => @weighting_factor }
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
        @offered = []
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
        path = Pick.face_path(view, x, y)
        # A move without the button down after a press means the host lost the release.
        cancel_gesture if collecting? && (flags.to_i & MK_LBUTTON).zero?
        if collecting?
          collect(path)
        else
          @hover = path
          view.tooltip = tooltip(path) if view.respond_to?(:tooltip=)
        end
        view.invalidate if view.respond_to?(:invalidate)
      rescue StandardError => error
        report_exception(error, view)
      end

      def onLButtonDown(_flags, x, y, view)
        @offered = []
        @pressed = true
        @gesture_edit_path = edit_path
        @factor = @weighting_factor
        @revision = @session.revision
        placement.refresh
        @collected = DragSet.new(:limit => Spaces.floor_gesture_limit)
        collect(Pick.face_path(view, x, y))
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

      def draw(view)
        draw_paths(view, @collected ? @collected.values.map { |item| item[:entities] } : [], COLLECTED_COLOUR)
        draw_paths(view, @hover ? [@hover] : [], HOVER_COLOUR) unless collecting?
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
        @offered = []
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

        kind, target = begin
          placement.place(entities)
        rescue CodedError => error
          [:refuse, error.message]
        end
        if kind == :refuse
          reset_gesture
          refuse(target)
          return
        end
        @collected.add(entities.map(&:persistent_id), { :kind => kind, :target => target, :entities => entities })
      end

      def complete
        collected = @collected
        factor = @factor
        revision = @revision
        reset_gesture
        return if collected.nil? || collected.empty?

        items = collected.values
        # Every pick in one gesture must mean the same thing in the same place (MarkPlacement#place).
        places = items.map { |item| [item[:kind], item[:target]] }.uniq
        return refuse(MIXED) unless places.length == 1

        kind, target = places.first
        # Marking's operation owns the limit and refuses; adding a Volume and offering Create Space take
        # no gesture, so the gesture refuses here rather than writing the first part of what it crossed.
        return refuse(too_large) if collected.full? && kind != :mark

        paths = items.map { |item| item[:entities].map(&:persistent_id) }
        case kind
        when :mark then mark(paths, factor, revision)
        when :volume then add_volume(target, paths, factor, revision)
        else offer(paths)
        end
      end

      def mark(paths, factor, revision)
        outcome = invoke(MARK, { "faces" => paths, "weighting_factor" => factor }, revision)
        report(outcome, "Marked #{paths.length} #{paths.length == 1 ? 'Floor Segment' : 'Floor Segments'} at " \
                        "#{ColourModes.band(factor)}.")
      end

      def add_volume(space, paths, factor, revision)
        outcome = invoke(ADD_VOLUME, { "space" => space, "faces" => paths, "weighting_factor" => factor }, revision)
        report(outcome, "Added a Volume to the Space with #{paths.length} " \
                        "#{paths.length == 1 ? 'Floor Segment' : 'Floor Segments'}.")
      end

      # Nothing is written: the Faces are remembered, until the next gesture or the tool ends, for the Create
      # Space menu item, which shows what it would make before it makes it.
      def offer(paths)
        @offered = paths
        announce(OFFER)
      end

      def too_large
        "One Mark floor gesture takes at most #{Spaces.floor_gesture_limit} Faces. #{Outcome::NOTHING_WRITTEN}"
      end

      def invoke(name, params, revision)
        API.invoke(:context => context, :name => name, :params => params,
                   :request => { "sequence" => next_sequence, "expected_revision" => revision })
      end

      def report(outcome, done)
        if outcome.fetch("status") == "completed"
          announce(done)
        else
          announce(outcome.fetch("message"), outcome.fetch("status") == "refused" ? :warning : :error)
        end
      end

      def context
        @context ||= API.connect(:session_id => @session.id)
      end

      def placement
        @placement ||= MarkPlacement.new(@session, context)
      end

      def next_sequence
        @sequence += 1
      end

      def reset_gesture
        @collected = nil
        @pressed = false
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

        Sketchup.status_text = "Mark floor at weighting factor #{ColourModes.band(@weighting_factor)}: click or " \
                               "drag over Faces inside a Volume, or click a Face at a Space's root to add a Volume."
      end

      def tooltip(entities)
        return "" if entities.nil?

        kind, target = begin
          placement.current
          placement.place(entities)
        rescue CodedError => error
          [:refuse, error.message]
        end
        { :mark => "Mark as a Floor Segment at #{ColourModes.band(@weighting_factor)}",
          :volume => "Add a Volume to this Space from this Face", :offer => "Create Space from this Face" }
          .fetch(kind, kind == :refuse ? target : "")
      end

      def draw_paths(view, paths, colour)
        return if paths.empty? || !view.respond_to?(:draw)

        triangles = []
        segments = []
        paths.each do |entities|
          transform = entities[0...-1].reduce(Geom::Transformation.new) { |sum, entity| sum * entity.transformation }
          faces, outlines = ColourBy::Tessellation.call(entities.last, transform)
          triangles.concat(faces)
          segments.concat(outlines)
        end
        view.drawing_color = Sketchup::Color.new(*colour, FILL_ALPHA) if view.respond_to?(:drawing_color=)
        view.draw(GL_TRIANGLES, ColourBy::Tessellation.lift(triangles, view, 3.0)) unless triangles.empty?
        view.drawing_color = Sketchup::Color.new(*colour, OUTLINE_ALPHA) if view.respond_to?(:drawing_color=)
        view.draw(GL_LINES, ColourBy::Tessellation.lift(segments, view, 3.0)) unless segments.empty?
      end

      def report_exception(error, view)
        pending = !@collected.nil?
        reset_gesture
        @hover = nil
        Diagnostics.exception("mark_tool", error)
        announce("The Mark floor tool could not complete that. #{Outcome::NOTHING_WRITTEN}", :error) if pending
        view.tooltip = "" if view.respond_to?(:tooltip=)
        view.invalidate if view.respond_to?(:invalidate)
      end
    end

    module_function

    # This Model's Mark floor tool, created on first reach and held as session feature state, so its factor
    # survives the tool ending and a Model closing takes it with it.
    def mark_tool(session)
      session.feature_state(:spaces_mark_tool) { MarkTool.new(session) }
    end
  end
end
