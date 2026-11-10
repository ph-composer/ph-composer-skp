# frozen_string_literal: true

module PhComposer
  module Spaces
    # One Volume's prism as the Set Height tool last read it: `loops` holds each Floor Segment's world loops in metres.
    SetHeightCandidate = Struct.new(:volume, :loops, :prism, :bounds, keyword_init: true) do
      def path
        volume.path
      end

      def height
        volume.record["avg_ceiling_height_m"]
      end

      def reference
        { "volume_id" => volume.record.fetch("id"), "entity_path" => volume.path }
      end

      def prism_at(height_m)
        loops.filter_map { |segment| Prism.segment(segment, height_m) }
      end
    end

    # The Set Height tool (context/EXTENSIBILITY.md, "Viewport tools"): drag a Volume's prism or type a value in the
    # measurements box. It calls `update` like any other client and opens no operation of its own: an abandoned drag
    # writes nothing and one entry is one Undo step, the Model's last height included.
    #
    # It starts with the Volume the selection names already picked, a selected Volume or a Space's one Volume, so a
    # value can be typed at once. A Space with several Volumes, or no such selection, waits for a click on one.
    #
    # A prism is drawn, not modelled, so the pointer is tested against each visible Volume's prism (PrismPick)
    # rather than through the host's pick, skipping whatever an active section plane has cut away. The prisms are
    # read once per revision, and afresh on a press, never per pointer move. A Volume with no height is a flat
    # prism on its floor, so it can be picked and given one.
    #
    # A press picks the Volume and freezes its height and the revision. Moving past DRAG_PIXELS makes it a drag,
    # whose top follows the pointer from where it was grabbed; a press released in place leaves the Volume picked
    # for typing. A typed value is its own gesture: it reads the picked Volume and the revision when it arrives.
    class SetHeightTool
      UPDATE = "#{FEATURE_ID}.update"
      KEY = "avg_ceiling_height_m"
      DRAG_PIXELS = 3
      HOVER_COLOUR = [184, 59, 59].freeze
      PICKED_COLOUR = [47, 143, 131].freeze
      INSTRUCTIONS = "Set Height: click a Volume, then drag its top or type a height."
      PICKED = "Set Height: drag the top of the Space, or type a height."
      CANCELLED = "The Set Height drag was cancelled. Nothing was written."
      NOTHING_PICKED = "Click a Space first, then type its height."
      BAD_ENTRY = "Type a height above zero, such as 2.5m or 8'."
      TOO_LOW = "A Volume's height must be above its floor."
      GONE = "That Volume no longer exists."

      # `moved` is past DRAG_PIXELS; `adjusted` is that a ray has given a height, which a straight-down view never does.
      Drag = Struct.new(:candidate, :anchor, :x, :y, :revision, :height, :moved, :adjusted, keyword_init: true)

      def self.install(feature)
        feature.menu_item("#{FEATURE_ID}.set_height_menu", :label => "Set Height", :menu => EXTENSION_NAME,
                                                           :available => lambda { |read|
                                                             !EditFloorSurfaceMenu.selected(read.session).nil?
                                                           }) do |session|
          Spaces.set_height_tool(session).start
        end
      end

      def initialize(session)
        @session = session
        @sequence = 0
        @candidates = []
      end

      # Chosen again while it runs, only the target changes.
      def start
        model = @session.model
        if active?
          pick_selected
        elsif model.respond_to?(:select_tool)
          model.select_tool(self)
        end
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

      # Sketchup::Tool. The host calls these; nothing else does.

      def activate
        @active = true
        pick_selected
      end

      def deactivate(view)
        @active = false
        cancel_drag
        @hover = nil
        @picked_path = nil
        view.invalidate if view.respond_to?(:invalidate)
      end

      # Escape ends the tool with its pending drag; any other cancel takes only the drag.
      def onCancel(reason, _view)
        cancel_drag
        stop if reason.to_i.zero?
      end

      def suspend(view)
        cancel_drag
        view.invalidate if view.respond_to?(:invalidate)
      end

      def resume(view)
        view.invalidate if view.respond_to?(:invalidate)
      end

      def onMouseMove(flags, x, y, view)
        # A move without the button down after a press means the host lost the release.
        cancel_drag if @drag && (flags.to_i & MK_LBUTTON).zero?
        @drag ? follow(x, y, view) : @hover = hit(x, y, view)&.first
        view.invalidate if view.respond_to?(:invalidate)
      rescue StandardError => error
        report_exception(error, view)
      end

      def onLButtonDown(_flags, x, y, view)
        @picked_path = nil
        forget_read
        candidates
        return refuse(@read_error) if @read_error

        candidate, anchor = hit(x, y, view)
        return arm(nil, view) unless candidate

        @drag = Drag.new(:candidate => candidate, :anchor => anchor, :x => x, :y => y, :moved => false,
                         :revision => @session.revision, :height => candidate.height.to_f)
        @edit_path = edit_path
        arm(candidate, view)
      rescue StandardError => error
        report_exception(error, view)
      end

      def onLButtonUp(_flags, _x, _y, view)
        drag = @drag
        @drag = nil
        return unless drag

        if !Sketchup.active_model.equal?(@session.model) || @edit_path != edit_path
          announce(CANCELLED, :warning)
        elsif drag.adjusted
          finish(drag)
        end
        view.invalidate if view.respond_to?(:invalidate)
      rescue StandardError => error
        report_exception(error, view, :notify => true)
      end

      def enableVCB?
        true
      end

      def onUserText(text, view)
        @drag = nil
        return refuse(@read_error || NOTHING_PICKED) unless @picked_path

        forget_read
        candidate = picked
        return refuse(@read_error || GONE) unless candidate

        height = parse(text)
        return refuse(BAD_ENTRY) unless height

        write(candidate, height, @session.revision)
        view.invalidate if view.respond_to?(:invalidate)
      rescue StandardError => error
        report_exception(error, view, :notify => true)
      end

      def draw(view)
        candidate, height, colour = shown
        return unless candidate && view.respond_to?(:draw)

        # Read for this frame: toggling section cuts moves no revision.
        points = ColourBy::OccurrenceVisibility.new(@session.model).clip_segments(
          Prism.outline(candidate.prism_at(height)).flatten(1).map { |corner| inches(corner) }, candidate.path
        )
        return if points.empty?

        view.drawing_color = Sketchup::Color.new(*colour) if view.respond_to?(:drawing_color=)
        view.line_width = 3 if view.respond_to?(:line_width=)
        view.draw(GL_LINES, ColourBy::Tessellation.lift(points, view, 3.0))
        view.line_width = 1 if view.respond_to?(:line_width=)
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
        @drag = nil
        @hover = nil
        @picked_path = nil
        return unless @active

        @active = false
        model = @session.model
        model.select_tool(nil) if model.respond_to?(:select_tool)
      end

      private

      def edit_path
        Array(@session.model.active_path).map(&:persistent_id)
      end

      def forget_read
        @read_at = nil
      end

      def pick_selected
        @picked_path = nil
        forget_read
        arm(selected_candidate, @session.model.active_view)
      rescue StandardError => error
        report_exception(error, @session.model.active_view, :notify => true)
      end

      # The visible Volume the selection names, or nil when the user has to click one.
      def selected_candidate
        target = EditFloorSurfaceMenu.target(@session)
        return if target.is_a?(String)

        candidates.find { |candidate| candidate.path == target.last }
      end

      # Every visible Volume's prism, read once per revision. An unreadable record leaves nothing to pick and
      # says why at the next press or entry.
      def candidates
        revision = @session.revision
        return @candidates if @read_at == revision

        @read_error = nil
        @candidates = read_candidates
        @read_at = revision
        @candidates
      rescue CodedError => error
        @read_error = error.message
        @read_at = revision
        @candidates = []
      end

      def read_candidates
        @visibility = ColourBy::OccurrenceVisibility.new(@session.model)
        Occurrences.scan(@session.model).spaces.flat_map(&:volumes).filter_map do |volume|
          next unless @visibility.path_visible?(volume.path)

          loops = volume.segments.map { |segment| FaceCapture.call(segment.entity, segment.transform).loops_m }
          candidate = SetHeightCandidate.new(:volume => volume, :loops => loops)
          candidate.prism = candidate.prism_at(candidate.height.to_f)
          candidate.bounds = PrismPick.bounds(candidate.prism)
          candidate
        end
      end

      def picked
        candidates.find { |candidate| candidate.path == @picked_path }
      end

      # What is under the pointer: the nearest prism and the world point on it, in metres, or nil.
      def hit(x, y, view)
        origin, direction = ray(view, x, y)
        best = candidates.filter_map do |candidate|
          next unless candidate.bounds && PrismPick.crosses?(candidate.bounds, origin, direction)

          distance = PrismPick.distances(candidate.prism, origin, direction).find do |along|
            !@visibility.cut?(inches(at(origin, direction, along)), candidate.path)
          end
          [candidate, distance] if distance
        end.min_by(&:last)
        best && [best.first, at(origin, direction, best.last)]
      end

      def at(origin, direction, distance)
        origin.zip(direction).map { |start, step| start + (step * distance) }
      end

      def inches(point_m)
        Geom::Point3d.new(*point_m.map { |value| value / INCH_TO_M })
      end

      def ray(view, x, y)
        origin, direction = view.pickray(x, y)
        [[origin.x, origin.y, origin.z].map { |value| value.to_f * INCH_TO_M },
         [direction.x.to_f, direction.y.to_f, direction.z.to_f]]
      end

      def arm(candidate, view)
        @picked_path = candidate&.path
        show_measurement(candidate&.height)
        Sketchup.status_text = (candidate ? PICKED : INSTRUCTIONS) if Sketchup.respond_to?(:status_text=)
        view.invalidate if view.respond_to?(:invalidate)
      end

      def follow(x, y, view)
        drag = @drag
        drag.moved ||= (x - drag.x).abs + (y - drag.y).abs > DRAG_PIXELS
        return unless drag.moved

        rise = PrismPick.rise(drag.anchor, *ray(view, x, y))
        return unless rise

        drag.adjusted = true
        drag.height = [drag.candidate.height.to_f + rise, 0.0].max
        show_measurement(drag.height)
      end

      # A drag lands on the millimetre, so the table shows the value the pointer meant.
      def finish(drag)
        height = drag.height.round(3)
        return refuse(TOO_LOW) unless height.positive?
        return if height == drag.candidate.height

        write(drag.candidate, height, drag.revision)
      end

      def parse(text)
        length = Sketchup.parse_length(text.to_s)
        metres = length && length.to_f * INCH_TO_M
        metres if metres&.finite? && metres.positive?
      rescue ArgumentError
        nil
      end

      def write(candidate, height, revision)
        outcome = API.invoke(:context => context, :name => UPDATE,
                             :params => { "reference" => candidate.reference, "values" => { KEY => height },
                                          "expected_values" => { KEY => candidate.height } },
                             :request => { "sequence" => next_sequence, "expected_revision" => revision })
        if outcome.fetch("status") == "completed"
          show_measurement(height)
          announce("Height set to #{length_text(height)}.")
        else
          show_measurement(candidate.height)
          announce(outcome.fetch("message"), outcome.fetch("status") == "refused" ? :warning : :error)
        end
      end

      # The drag's live height, then the picked Volume, then the one under the pointer.
      def shown
        return [@drag.candidate, @drag.height, PICKED_COLOUR] if @drag

        current = @picked_path && picked
        return [current, current.height.to_f, PICKED_COLOUR] if current

        [@hover, @hover.height.to_f, HOVER_COLOUR] if @hover
      end

      def show_measurement(height_m)
        return unless Sketchup.respond_to?(:vcb_value=) && Sketchup.respond_to?(:format_length)

        Sketchup.vcb_label = "Height"
        Sketchup.vcb_value = height_m ? Sketchup.format_length(height_m / INCH_TO_M) : ""
      end

      def length_text(height_m)
        Units.format(height_m, :quantity => "length", :system => Preferences.unit_system)
      end

      def context
        @context ||= API.connect(:session_id => @session.id)
      end

      def next_sequence
        @sequence += 1
      end

      # A press that has not moved is only a pick, so losing it cancels nothing the user can see.
      def cancel_drag
        moved = @drag&.moved
        @drag = nil
        announce(CANCELLED, :warning) if moved
      end

      def refuse(message)
        announce("#{message} #{Outcome::NOTHING_WRITTEN}", :warning)
      end

      # Results and refusals reach the status bar, which a viewport tool always has, and the panel's notice.
      def announce(message, tone = :info)
        @session.notice(message, :tone => tone)
        Sketchup.status_text = message if Sketchup.respond_to?(:status_text=)
      end

      # A raised pointer move logs once and stays quiet unless a drag was under way; a release or a typed value
      # always says so, since the user is waiting on it.
      def report_exception(error, view, notify: false)
        pending = !@drag.nil?
        @drag = nil
        @hover = nil
        Diagnostics.exception("set_height_tool", error)
        message = "The Set Height tool could not complete that. #{Outcome::NOTHING_WRITTEN}"
        announce(message, :error) if pending || notify

        view.invalidate if view.respond_to?(:invalidate)
      end
    end

    module_function

    # This Model's Set Height tool, held as session feature state, so a Model closing takes it with it.
    def set_height_tool(session)
      session.feature_state(:spaces_set_height_tool) { SetHeightTool.new(session) }
    end
  end
end
