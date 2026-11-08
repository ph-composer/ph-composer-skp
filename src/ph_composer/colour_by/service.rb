# frozen_string_literal: true

module PhComposer
  module ColourBy
    # What a mode's projection returns, one per entity it paints. `transform` maps the entity's own
    # contents to world. `value` is what the mode groups and colours by; nil means the entity carries
    # no record yet, which every mode draws the same way. `label` is the legend's wording for that
    # value, defaulting to the value itself. A projection that knows a value is only half filled in
    # says so with `state: :incomplete`; the service paints that amber in every mode, because only
    # the owning feature knows what its own record still needs.
    # `path`, when supplied, is the full root-to-entity persistent-id path. It preserves ancestor
    # visibility for a flattened projection, including distinct occurrences of shared storage.
    # Without it the service can check only the entity and its descendants, as before.
    # `colour`, when supplied, is the entry's own `[r, g, b]`, for a mode whose colour is a property of the
    # record it groups by (an Assembly's colour) rather than a function of the value. `value` then stays a
    # plain legend key: the legend's select and isolate commands take a string or null.
    # `hatch_outline: false` keeps the unclassified hatch but leaves its boundary edges native.
    # Omission preserves the solid unclassified boundary used by other modes.
    # `derived`, when supplied, is a Derived: world-space shapes drawn in the entry's colour and state, with
    # or without an entity (context/EXTENSIBILITY.md, "Colour-by derived geometry").
    # `label` may also be a list of parts, as a readout line is (plain text or `[quantity, si_value]`), so a
    # unit-bearing label is formatted in the display units wherever it is shown. `figure`, when supplied, is
    # one `[quantity, si_value]` the legend sums per row and shows beside the count (an area, a volume), or a
    # list of them summed position by position (supply and extract).
    Entry = Struct.new(:entity, :transform, :value, :label, :state, :path, :colour, :hatch_outline, :derived,
                       :figure, keyword_init: true)

    # World-space shapes in SketchUp's inches: `polygons`, planar loops of points, filled and outlined;
    # `segments`, pairs of points drawn as lines. The projection owns every conversion to world.
    Derived = Struct.new(:polygons, :segments, keyword_init: true)

    # What a readout's projection returns: `anchors`, text placed at world points, and `hud`, lines drawn
    # under the legend. A line is a list of parts: plain text, or `[quantity, si_value]`, which the overlay
    # formats in the session's display units.
    Readout = Struct.new(:anchors, :hud, keyword_init: true)

    # One line of viewport text at a world `point` (inches). `path`, when given, hides it with that
    # occurrence and mutes it under the occurrence mask, as an entry's shapes are.
    Anchor = Struct.new(:point, :parts, :path, keyword_init: true)

    # One legend row: a colour, what it means (text or parts), how many entities carry it, which of the
    # three states it is in (`classified`, `incomplete` or `unclassified`), and its entries' summed `figure`, a
    # list of `[quantity, si_value]` pairs.
    Row = Struct.new(:value, :label, :colour, :count, :state, :figure, keyword_init: true)

    # One Model's Colour-by state: which mode is active, the cached drawing for it, and the overlay
    # that draws it. Reached through `ColourBy.for(session)`; the session holds it as generic feature
    # state and names no mode.
    #
    # The cache is whole and keyed on the session revision, which advances on a committed change,
    # Undo, Redo and an edit-path change (context/CONTRACTS.md, "Revisions, transactions and host
    # execution"). A tag being hidden changes what may be painted without necessarily advancing that
    # revision, so `tags_changed` forces a rebuild. Rebuilding happens when the invalidating event
    # arrives, never inside `draw`: a draw callback repairs nothing (context/TECH_STACK.md).
    #
    # Scene tag visibility reaches the layer invalidation path, verified on SketchUp 26.1. Other scene
    # visibility state is not verified; there is no general scene-change subscription here.
    class Service
      attr_reader :mode_name, :rows, :fills, :outlines, :unclassified_outlines, :unclassified_hatch, :isolated
      attr_reader :lines, :readouts_on, :readout_drawings
      attr_reader :filter_paths
      # How many times the drawing has been rebuilt for this Model. The host walkthrough reads it to
      # tell an invalidating event that fired from one that did not.
      attr_reader :rebuilds
      # How many times a mode has been turned on or off, so a ColourBy::Lease tells a change since its own
      # take from none, even when the user picked the same mode again.
      attr_reader :switches

      def initialize(session)
        @session = session
        @rebuilds = 0
        @filter_paths = nil
        @readouts_on = []
        @readout_drawings = {}
        @selection_generation = 0
        @switches = 0
        clear
        # An extension action can receive SketchUp's commit callback before ModelSession#mutate
        # advances the revision. Its later change publication is the first safe rebuild point.
        # Native changes still arrive through the host-event subscriptions in install.rb.
        @change_unsubscribe = Sessions.on_change do |changed_session, _source, _detail|
          invalidate! if changed_session.equal?(@session)
        end
      end

      def active?
        !@mode_name.nil?
      end

      def mode
        @mode_name && Registry.current.colour_modes[@mode_name]
      end

      # Turns a mode on, remembering it as the one the user last chose. Nothing about the Model
      # changes: no record is written, no material is assigned and no operation opens.
      #
      # `remember: false` turns a mode on without recording the choice. A viewport tool's mode
      # (ColourBy::Lease) is not what the user chose, so it must not displace the remembered mode.
      def activate(name, remember: true)
        declaration = Registry.current.colour_modes[name]
        raise UserError, "There is no Colour-by mode named #{name}." unless declaration

        @switches += 1
        @mode_name = name
        # A row belongs to the mode it came from, so a new mode starts showing everything.
        @isolated = nil
        rebuild
        if active?
          attach_overlay
          remember_mode(name) if remember
        end
        self
      end

      def deactivate
        @switches += 1
        clear
        detach_overlay if @readouts_on.empty?
        invalidate_view
        self
      end

      # The drawing is stale: rebuild it now, while the host event that invalidated it is being
      # handled, and repaint. Does nothing while no mode is active. Several events can report one
      # user action, so a rebuild at a revision already drawn is skipped; `force` is for what the
      # revision does not cover, such as a tag being hidden.
      def invalidate!(force: false)
        rebuild if active? && (force || @built_key != safely { build_key })
        rebuild_readouts if !@readouts_on.empty? && (force || @readouts_built != safely { readout_key })
        self
      end

      # Turns a readout on or off for this Model session, whatever mode is on. Nothing is remembered
      # across sessions and nothing about the Model changes.
      def readout(name, on:)
        known = Registry.current.colour_readouts.key?(name)
        raise UserError, "There is no Colour-by readout named #{name}." unless known

        @readouts_on = on ? (@readouts_on | [name]) : (@readouts_on - [name])
        @readout_drawings = @readout_drawings.slice(*@readouts_on)
        rebuild_readouts
        @readouts_on.empty? && !active? ? detach_overlay : attach_overlay
        invalidate_view
        self
      end

      # The selection changed: readouts that read it are stale, and nothing else is.
      def selection_changed
        @selection_generation += 1
        reading = @readouts_on.select { |name| Registry.current.colour_readouts[name]&.selection }
        return self if reading.empty?

        rebuild_readouts(reading)
        self
      end

      # A detach counts as a switch, so a tool ending after it gives back no mode (ColourBy::Lease).
      def detach
        @switches += 1
        clear
        @readouts_on = []
        @readout_drawings = {}
        detach_overlay
        @change_unsubscribe.call
        self
      end

      def legend
        system = Preferences.unit_system
        {
          "mode" => @mode_name, "label" => mode&.label, "entity_kind" => mode&.entity_kind,
          "isolated" => @isolated && { "value" => @isolated.first, "state" => @isolated.last.to_s },
          "filter_paths" => @filter_paths && @filter_paths.map(&:dup),
          "rows" => rows.map do |row|
            text = { "value" => row.value, "label" => ReadoutOutput.text(row.label, system),
                     "colour" => row.colour.dup, "count" => row.count, "state" => row.state.to_s,
                     "isolated" => @isolated == [row.value, row.state] }
            # Only a row whose entries give a figure has one, formatted in the display units.
            row.figure ? text.merge("figure" => Legend.figure_text(row.figure, system)) : text
          end
        }
      end

      # Selects the entities one legend row stands for and brings them into view: the legend's own
      # Locate. It counts an entity the drawing omits, a hidden Face or one on a hidden tag, because
      # the legend tells the truth about the Model rather than about the viewport. Such an entity is
      # still selected here; SketchUp shows the selection where it can, and a count the user can reach
      # nothing from would be worse than one that reaches a hidden thing.
      def select_row(value, state)
        model = live_model
        # The cache holds live entities from the last rebuild. One can be erased by something that
        # raised no event this service subscribes to, and `Selection#add` on an erased entity raises,
        # which would reach the client as a bare failure rather than as an answer.
        key = [value, state.to_sym]
        placed = @entities.fetch(key, [])
                          .select { |entity, _transform| entity.respond_to?(:valid?) ? entity.valid? : true }
        shapes = @frames.fetch(key, [])
        raise UserError, "That legend row is no longer part of this drawing." if (placed.empty? && shapes.empty?) ||
                                                                                 model.nil?

        # Shapes with no entity are framed but select nothing: there is nothing to select.
        entities = placed.map(&:first)
        model.selection.clear
        model.selection.add(entities) unless entities.empty?
        view = model.respond_to?(:active_view) ? model.active_view : nil
        # Framed by where the entities are in the world, from the transforms the entries carried: a Face
        # inside a closed Zone Group is framed where it is, not by its Group's own coordinates.
        points = placed.flat_map { |entity, transform| Tessellation.call(entity, transform).first } + shapes
        ViewFraming.call(view, points, entities)
        entities.length
      end

      # Shows one row on its own, everything else muted, or clears that with nil. It repaints rather
      # than filtering at draw time, because a draw callback repairs nothing.
      def isolate(row)
        raise UserError, "Colour by is off, so there is nothing to show on its own." unless active?

        @isolated = row && [row.first, row.last.to_sym]
        rebuild
        self
      end

      # An occurrence mask belongs to the session, independently of the mode. Tables can change it
      # while Colour by is off, and a mode switch keeps it. Prefix indexes distinguish shared
      # occurrences without comparing every drawn Face with every requested path.
      def filter(paths)
        @isolated = nil
        @filter_paths = paths && paths.map { |path| path.dup.freeze }.uniq.freeze
        @filter_roots = (@filter_paths || []).to_h { |path| [path, true] }
        @filter_ancestors = {}
        @filter_roots.each_key do |path|
          path.each_index { |index| @filter_ancestors[path[0..index]] = true }
        end
        rebuild if active?
        rebuild_readouts unless @readouts_on.empty?
        self
      end

      private

      def clear
        @mode_name = nil
        @rows = []
        @fills = {}
        @outlines = {}
        @unclassified_outlines = []
        @unclassified_hatch = []
        @lines = {}
        @frames = {}
        @entities = {}
        @isolated = nil
        @built_key = nil
      end

      def rebuild
        declaration = mode
        return deactivate unless declaration

        view_state = ViewState.new(@session.model)
        drawing = Drawing.new(:visibility => OccurrenceVisibility.new(@session.model, view_state),
                              :set_aside => method(:set_aside?), :in_filter => method(:matches_filter?))
        read = HandlerRequest.for(@session, :owner => declaration.owner, :name => declaration.name)
        painted = Array(declaration.projection.call(read)).map do |entry|
          [entry, *paint(declaration, entry)]
        end
        # A row the user set aside can stop existing: the last Wall becomes a Floor, or its Zone is
        # deleted. Keeping the isolation then mutes everything and leaves no row offering to undo it,
        # so a row that is gone releases what it was holding.
        @isolated = nil unless painted.any? { |entry, state, _colour| [entry.value, state] == @isolated }
        painted.each { |entry, state, colour| drawing.add(entry, state, colour) }
        publish(declaration, drawing, view_state)
        @built_key = [@session.revision, view_state.key]
        @rebuilds += 1
        invalidate_view
      rescue StandardError => error
        # Projection, colour assignment, tessellation and ordering are all contributor/host reads.
        # A failure anywhere in that pipeline must not abort later host-event subscribers or leave
        # a partial drawing active. The next snapshot reports Off alongside the warning.
        failed(declaration, error)
      end

      # The mode is already showing; a choice the host could not remember only costs the next session its default.
      def remember_mode(name)
        Preferences.set("colour_by_mode", name)
      rescue UserError => error
        Diagnostics.exception("colour_by_mode_not_remembered", error)
      end

      # The mode is off, the overlay is gone and the user is told which mode stopped drawing.
      def failed(declaration, error)
        Diagnostics.log("colour_by_failed", "operation" => declaration.name, "error_class" => error.class.name)
        deactivate
        @session.notice("#{declaration.label} could not be drawn, so Colour by is off.", :tone => :warning)
        self
      end

      # Replaces the drawing the overlay reads with a completed one. The two steps that can still raise,
      # the mode's ordering and the hatch, run before anything is assigned.
      def publish(declaration, drawing, view_state)
        rows = order(declaration, drawing.rows)
        hatch = Tessellation.hatch(view_state.clip_triangles(drawing.unclassified_triangles))
        @rows = rows
        @entities = drawing.entities
        @frames = drawing.frames
        @fills = drawing.fills.transform_values { |points| view_state.clip_triangles(points) }
        @outlines = drawing.outlines.transform_values { |points| view_state.clip_segments(points) }
        @lines = drawing.lines.transform_values { |points| view_state.clip_segments(points) }
        @unclassified_outlines = view_state.clip_segments(drawing.unclassified_outlines)
        @unclassified_hatch = hatch
      end

      # A read of the view state that raises answers no key, so the rebuild's own failure path handles it.
      def safely
        yield
      rescue StandardError => error
        Diagnostics.exception("colour_by_view_state", error)
        nil
      end

      def build_key
        [@session.revision, ViewState.new(@session.model).key]
      end

      # Rebuilds `names`, every readout on by default, keeping the others' drawings. A readout that fails
      # goes off, and the overlay goes with the last thing it was drawing.
      def rebuild_readouts(names = @readouts_on)
        @readouts_built = readout_key if names.equal?(@readouts_on)
        rebuilt = names.to_h { |name| [name, readout_drawing(name)] }
        @readout_drawings = @readout_drawings.merge(rebuilt).slice(*@readouts_on).compact
        detach_overlay if @readouts_on.empty? && !active?
        invalidate_view
      end

      def readout_key
        [@session.revision, @selection_generation, ViewState.new(@session.model).key]
      end

      # One readout's anchors and HUD lines, with hidden and muted anchors left out. A readout that raises
      # is turned off with a notice, as a mode is; the rest keep drawing.
      def readout_drawing(name)
        declaration = Registry.current.colour_readouts.fetch(name)
        read = HandlerRequest.for(@session, :owner => declaration.owner, :name => declaration.name,
                                            :selection => declaration.selection ? selected_paths : nil)
        result = ReadoutOutput.check!(declaration.projection.call(read))
        view_state = ViewState.new(@session.model)
        visibility = OccurrenceVisibility.new(@session.model, view_state)
        anchors = Array(result.anchors).select do |anchor|
          masked = anchor.path.nil? ? !@filter_paths.nil? : !matches_filter?(anchor.path)
          visibility.path_visible?(anchor.path) && !masked && !view_state.cut?(anchor.point)
        end
        [anchors, Array(result.hud)]
      rescue StandardError => error
        Diagnostics.log("colour_readout_failed", "operation" => name, "error_class" => error.class.name)
        @readouts_on -= [name]
        @session.notice("#{declaration&.label || name} could not be drawn, so it is off.", :tone => :warning)
        nil
      end

      # The selected occurrences as full persistent-id paths: the open edit path and each selected entity.
      def selected_paths
        model = @session.model
        open = Array(model.active_path).map(&:persistent_id)
        model.selection.to_a.map { |entity| open + [entity.persistent_id] }
      end

      def set_aside?(value, state)
        !@isolated.nil? && @isolated != [value, state]
      end

      def matches_filter?(path)
        return true if @filter_paths.nil?
        return false if path.nil?
        return true if @filter_ancestors.key?(path)

        path.each_index.any? { |index| @filter_roots.key?(path[0..index]) }
      end

      # The three states every mode shares: no record at all, a record this mode cannot finish
      # colouring, and a value the mode has a hue for.
      #
      # A projection's own `:incomplete` is asked first, before the value is looked at. An entity
      # that carries a record but no value for this mode's field is incomplete, not unclassified:
      # the user did classify it, and telling them otherwise sends them to Suggest classification,
      # which never touches a Face that already has a record.
      def paint(declaration, entry)
        return [:incomplete, Palette::INCOMPLETE] if entry.state == :incomplete
        return [:unclassified, Palette::UNCLASSIFIED] if entry.value.nil?

        colour = entry.colour || declaration.colours.call(entry.value)
        colour ? [:classified, colour] : [:incomplete, Palette::INCOMPLETE]
      end

      def order(declaration, rows)
        return rows.sort_by(&declaration.sort) if declaration.sort

        rows.sort_by { |row| [row.state == :unclassified ? 1 : 0, -row.count, ReadoutOutput.text(row.label, "SI")] }
      end

      # An overlay SketchUp accepts is not an overlay SketchUp draws. `OverlaysManager#add` leaves
      # it disabled, so it appears unticked in the Overlays panel and `draw` is never called; a
      # mode turned on drew nothing at all until this was measured on 26.1.188, 2026-09-20.
      # Enabling it here is right because it is added when a mode is turned on and removed when the
      # mode goes off, so this never overrides a choice the user made about an overlay of ours that
      # is sitting there.
      def attach_overlay
        return unless live_model

        @overlay ||= Overlay.new(self)
        live_model.overlays.add(@overlay)
        @overlay.enabled = true if @overlay.respond_to?(:enabled=)
      end

      # A closed Model still answers `respond_to?(:overlays)`, and reading them raises. The session
      # is already marked detached by the time feature state is torn down, so the Model itself is
      # what decides whether there is anything left to remove the overlay from.
      def detach_overlay
        overlay = @overlay
        @overlay = nil
        return unless overlay && live_model

        live_model.overlays.remove(overlay)
      end

      def live_model
        model = @session.model
        return nil unless model.respond_to?(:overlays)

        model.respond_to?(:valid?) && !model.valid? ? nil : model
      end

      def invalidate_view
        model = live_model
        view = model.respond_to?(:active_view) ? model.active_view : nil if model
        view&.invalidate
      end
    end
  end
end
