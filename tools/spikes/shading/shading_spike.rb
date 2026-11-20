# frozen_string_literal: true

# SD01 spike: does the Shading mark survive native edits? Development only, never shipped. Loaded into
# SketchUp through the development bridge:
#
#   load "<repo>/tools/spikes/shading/shading_spike.rb"
#   ShadingSpike.setup        # builds the islands; returns what it built, counted by construction
#   ShadingSpike.look(:copy)  # camera on one island, so a viewport point is on screen
#   ShadingSpike.select(:copy, :face, :group, :instance)   # the native selection a gesture starts from
#   ShadingSpike.scan         # every marked entity and every Shading Face occurrence, by island
#
# The mark is the record Shading will write: dictionary `ph_composer.shading`, key `record`, the canonical
# JSON `{"schema_version":1}`. `setup` writes it with `set_attribute` (development eval, not the feature),
# and labels each target in a second dictionary so a scan can name it after the gesture.
#
# Every island at the Model root holds the same three marked targets: a loose Face, a Group of a box with a
# nested unnamed Group, and a ComponentInstance of a two-Face fin placed once. Islands sit 10 m apart in x;
# a scan assigns each root entity to the island its bounds centre falls in, so a copy moved along y stays
# in its island. `scan` only reads: it opens no operation and creates no dictionary, so Redo survives it.
require "json"

module ShadingSpike
  DICTIONARY = "ph_composer.shading"
  KEY = "record"
  MARK = '{"schema_version":1}'
  LABEL = "phc_shading_spike"
  ISLAND_PITCH_M = 10.0
  CASES = %i[copy array cut make_group make_component make_unique pushpull divide intersect explode].freeze
  EXTRA = %i[shared visibility].freeze
  # Per gesture island, by construction: the loose Face, the box's six Faces and the nested Group's one, and
  # the fin's two. Marked rows count occurrences, so a marked definition Face counts once per placement.
  BUILT = { "face_occurrences" => 10, "shading_face_occurrences" => 10, "marked_rows" => 3 }.freeze
  BUILT_EXCEPTIONS = {
    "make_unique" => { "face_occurrences" => 12, "shading_face_occurrences" => 11, "marked_rows" => 5 },
    "intersect" => { "face_occurrences" => 11, "shading_face_occurrences" => 10, "marked_rows" => 3 },
    "shared" => { "face_occurrences" => 4, "shading_face_occurrences" => 4, "marked_rows" => 4 },
    "visibility" => { "face_occurrences" => 3, "shading_face_occurrences" => 3, "marked_rows" => 3 }
  }.freeze

  class << self
    def model
      Sketchup.active_model
    end

    def setup
      raise "ShadingSpike.setup needs an empty Model." unless model.entities.length.zero?

      @marked_pids = Hash.new { |hash, key| hash[key] = [] }
      operation("SD01 setup") do
        CASES.each_with_index { |name, index| island(name, index) }
        @island = "shared"
        shared(CASES.length)
        @island = "visibility"
        visibility(CASES.length + 1)
      end
      built
    end

    # What `setup` wrote, from its own bookkeeping and the counts above, never from a scan: the recorder is
    # checked against this.
    def built
      (CASES.map(&:to_s) + EXTRA.map(&:to_s)).to_h do |name|
        [name, BUILT_EXCEPTIONS.fetch(name, BUILT).merge("marked_pids" => @marked_pids[name].sort)]
      end
    end

    # The scan of each island reduced to the shape `built` returns.
    def check(built_islands)
      scanned = scan.fetch("islands")
      built_islands.to_h do |name, want|
        found = scanned.fetch(name, {})
        rows = found.fetch("marked", [])
        got = { "face_occurrences" => found["face_occurrences"],
                "shading_face_occurrences" => found["shading_face_occurrences"], "marked_rows" => rows.length,
                "marked_pids" => rows.map { |row| row["pid"] }.uniq.sort }
        [name, got == want ? "ok" : { "built" => want, "scanned" => got }]
      end
    end

    def look(name)
      root = model.entities.to_a.select { |entity| island_of(entity) == name.to_s }
      bounds = Geom::BoundingBox.new
      root.each { |entity| bounds.add(entity.bounds) }
      centre = bounds.center
      eye = centre.offset(Geom::Vector3d.new(-6000.mm, -9000.mm, 7000.mm))
      model.active_view.camera = Sketchup::Camera.new(eye, centre, Z_AXIS)
      centre.to_a.map(&:to_mm).map(&:round)
    end

    # The island's targets by role, as the native selection: `:face` (the loose Face), `:face_edges` (its
    # bounding Edges too), `:edge` (its south Edge), `:group`, `:instance`, `:instance2`, `:blade`.
    def select(name, *roles)
      chosen = roles.flat_map { |role| targets(name, role) }
      model.selection.clear
      model.selection.add(chosen)
      model.selection.map { |entity| [entity.typename, entity.persistent_id] }
    end

    def targets(name, role)
      root = model.entities.to_a.select { |entity| island_of(entity) == name.to_s }
      labelled = ->(want) { root.select { |entity| entity.get_attribute(LABEL, "role") == want } }
      case role
      when :face_edges then labelled.call("face").flat_map { |face| [face] + face.edges }
      when :edge then labelled.call("face").map { |face| face.edges.min_by { |edge| edge.bounds.center.y } }
      else labelled.call(role.to_s)
      end
    end

    def scan
      rows = []
      walk(model.entities, { :island => nil, :path => [], :names => [], :marked_above => false }, rows)
      islands = rows.group_by { |row| row.fetch("island") }.transform_values do |list|
        marked = list.select { |row| row["mark"] }
        { "marked" => marked.map { |row| row.reject { |key, _| key == "island" } },
          "shading_face_occurrences" => list.count { |row| row["kind"] == "Face" && row["shading"] },
          "face_occurrences" => list.count { |row| row["kind"] == "Face" } }
      end
      { "islands" => islands.sort.to_h, "definitions" => definitions }
    end

    # Read-only Faces of the visibility island through the extension's export snapshot (question 5) and the
    # host's loop order (question 4).
    def visibility_read
      snapshot = PhComposer::Export::GeometrySnapshot.capture(model, :revision => 0)
      faces = targets(:visibility, :face) + targets(:visibility, :hidden) + targets(:visibility, :tag_hidden)
      faces.map do |face|
        entry = snapshot.entries.find { |candidate| candidate.kind == "face" && candidate.path == [face.persistent_id] }
        { "role" => face.get_attribute(LABEL, "role"), "hidden" => face.hidden?, "tag_visible" => face.layer.visible?,
          "loops" => face.loops.length, "outer_first" => face.loops.first == face.outer_loop,
          "in_snapshot" => !entry.nil?, "snapshot_loops" => entry && entry.geometry.loops_m.length }
      end
    end

    private

    def operation(name)
      model.start_operation(name, true)
      yield
      model.commit_operation
    rescue StandardError
      model.abort_operation
      raise
    end

    def mark(entity, role)
      entity.set_attribute(DICTIONARY, KEY, MARK)
      @marked_pids[@island] << entity.persistent_id
      label(entity, role)
    end

    # A mark on a definition's own Face: one entity, read once per placement.
    def mark_definition_face(face)
      face.set_attribute(DICTIONARY, KEY, MARK)
      @marked_pids[@island] << face.persistent_id
    end

    def label(entity, role)
      entity.set_attribute(LABEL, "role", role)
      entity
    end

    def origin(index)
      (index * ISLAND_PITCH_M * 1000).mm
    end

    def island(name, index)
      @island = name.to_s
      x = origin(index)
      mark(square(model.entities, x, 0, 2000.mm), "face")
      group = model.entities.add_group
      group.name = "G_#{name}"
      box(group.entities, 3000.mm, 0, 1000.mm)
      nested = group.entities.add_group
      square(nested.entities, 3000.mm, 1500.mm, 500.mm)
      group.transformation = Geom::Transformation.new([x, 0, 0])
      mark(group, "group")
      definition = fin("C_#{name}")
      mark(model.entities.add_instance(definition, Geom::Transformation.new([x + 5000.mm, 0, 0])), "instance")
      second_placement(definition, x) if name == :make_unique
      blade(x) if name == :intersect
    end

    # Make Unique needs storage two placements share: a second, unmarked placement, and a mark on one Face of
    # the definition, the Face mark behind shared storage of D5s-16.
    def second_placement(definition, x)
      label(model.entities.add_instance(definition, Geom::Transformation.new([x + 5000.mm, 3000.mm, 0])), "instance2")
      mark_definition_face(definition.entities.grep(Sketchup::Face).min_by { |face| face.bounds.center.x })
    end

    # A vertical Face in its own Group crossing the loose Face and the box, for Intersect Faces > With Model.
    def blade(x)
      group = model.entities.add_group
      group.entities.add_face([x + 1000.mm, -500.mm, -500.mm], [x + 1000.mm, 3000.mm, -500.mm],
                              [x + 1000.mm, 3000.mm, 1500.mm], [x + 1000.mm, -500.mm, 1500.mm])
      label(group, "blade")
    end

    # A Component placed twice with both definition Faces marked: one mark, two occurrences.
    def shared(index)
      x = origin(index)
      definition = fin("C_shared")
      definition.entities.grep(Sketchup::Face).each { |face| mark_definition_face(face) }
      label(model.entities.add_instance(definition, Geom::Transformation.new([x, 0, 0])), "instance")
      label(model.entities.add_instance(definition, Geom::Transformation.new([x, 3000.mm, 0])), "instance2")
    end

    # A holed Face, a hidden Face and a Face on a hidden tag, all marked.
    def visibility(index)
      x = origin(index)
      holed = square(model.entities, x, 0, 3000.mm)
      inner = model.entities.add_face([x + 1000.mm, 1000.mm, 0], [x + 2000.mm, 1000.mm, 0],
                                      [x + 2000.mm, 2000.mm, 0], [x + 1000.mm, 2000.mm, 0])
      inner.erase!
      raise "The holed Face did not get an inner loop." unless holed.valid? && holed.loops.length == 2

      mark(holed, "face")
      hidden = mark(square(model.entities, x, 4000.mm, 1000.mm), "hidden")
      hidden.hidden = true
      tag = model.layers["sd01_hidden_tag"] || model.layers.add("sd01_hidden_tag")
      tagged = mark(square(model.entities, x, 6000.mm, 1000.mm), "tag_hidden")
      tagged.layer = tag
      tag.visible = false
    end

    def square(entities, x, y, size)
      face = entities.add_face([x, y, 0], [x + size, y, 0], [x + size, y + size, 0], [x, y + size, 0])
      face.reverse! if face.normal.z.negative?
      face
    end

    def box(entities, x, y, size)
      floor = entities.add_face([x, y, 0], [x, y + size, 0], [x + size, y + size, 0], [x + size, y, 0])
      floor.reverse! if floor.normal.z.positive?
      floor.pushpull(-size)
    end

    def fin(name)
      definition = model.definitions.add(name)
      definition.entities.add_face([0, 0, 0], [1000.mm, 0, 0], [1000.mm, 0, 1000.mm], [0, 0, 1000.mm])
      definition.entities.add_face([1500.mm, 0, 0], [2500.mm, 0, 0], [2500.mm, 0, 1000.mm], [1500.mm, 0, 1000.mm])
      definition
    end

    def island_of(entity)
      index = (entity.bounds.center.x.to_mm / (ISLAND_PITCH_M * 1000)).floor
      all = CASES + EXTRA
      index.between?(0, all.length - 1) ? all[index].to_s : "outside"
    end

    # `marked_above` carries a mark on any container between the root and here: the Shading Face rule
    # without the Zone and claim stops, which this fixture has none of. `island` is the root entity's.
    def walk(entities, context, rows)
      entities.each do |entity|
        next unless entity.is_a?(Sketchup::Face) || entity.is_a?(Sketchup::Group) ||
                    entity.is_a?(Sketchup::ComponentInstance)

        island = context[:island] || island_of(entity)
        mark = entity.get_attribute(DICTIONARY, KEY)
        path = context[:path] + [entity.persistent_id]
        row = { "island" => island, "kind" => entity.typename, "pid" => entity.persistent_id, "path" => path,
                "names" => context[:names], "mark" => mark, "role" => entity.get_attribute(LABEL, "role"),
                "shading" => context[:marked_above] || !mark.nil? }
        rows << row.merge(details(entity))
        next if entity.is_a?(Sketchup::Face)

        name = entity.name.empty? ? entity.definition.name : entity.name
        walk(entity.definition.entities, { :island => island, :path => path, :names => context[:names] + [name],
                                           :marked_above => row["shading"] }, rows)
      end
    end

    def details(entity)
      if entity.is_a?(Sketchup::Face)
        { "area_m2" => (entity.area * 0.0254 * 0.0254).round(4), "loops" => entity.loops.length }
      else
        definition = entity.definition
        { "name" => entity.name, "definition" => definition.persistent_id, "definition_name" => definition.name,
          "instances" => definition.instances.length }
      end
    end

    # Each definition holding a mark on itself or on a child, with how many placements share it.
    def definitions
      model.definitions.filter_map do |definition|
        own = definition.get_attribute(DICTIONARY, KEY)
        children = definition.entities.count { |entity| !entity.get_attribute(DICTIONARY, KEY).nil? }
        next if own.nil? && children.zero?

        { "name" => definition.name, "pid" => definition.persistent_id, "group" => definition.group?,
          "instances" => definition.instances.length, "own_mark" => own, "marked_children" => children }
      end.sort_by { |row| row["name"] }
    end
  end
end
