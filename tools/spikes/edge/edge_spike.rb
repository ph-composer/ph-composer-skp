# frozen_string_literal: true

# B4 spike: edge identity (planning/archive/phase-00-foundation/phases/phase-01-investigations.md). Development only,
# never shipped. Loaded into SketchUp through the development bridge after the B3 spike file:
#
#   load "<repo>/tools/spikes/window/window_spike.rb"
#   load "<repo>/tools/spikes/edge/edge_spike.rb"
#   EdgeSpike.setup                 # tagged edges in five situations, plus a Model-level registry
#   EdgeSpike.run(:split)           # one operation, then an observer-free scan against the registry
#   EdgeSpike.scan                  # classify every assignment: kept, replaced, split, duplicated, lost
#
# Tags are synthetic: a type id, an assignment id and a namespaced JSON payload on each edge. The registry
# is what a feature record would hold: assignment id to the edge persistent ids it was made on.
#
# The cases B4 left open (planning/archive/phase-03b-thermal-bridges, stage P3b-01), each followed by
# native Undo, Redo, save and a fresh-process reopen, read with `EdgeSpike.scan` after every step:
#
#   EdgeSpike.run(:crossing)        # a line drawn up the south wall splits the tagged base edge in two
#   EdgeSpike.run(:heal)            # erasing that line heals the halves; which dictionary survives is the question
#   EdgeSpike.run(:crossing); EdgeSpike.run(:retag_half); EdgeSpike.run(:heal)   # halves tagged differently
#   EdgeSpike.run(:intersect)       # Entities#intersect_with of a crossing face through the base edge
#   EdgeSpike.run(:collapse)        # a push-pull that deletes the tagged corner edge (roof pushed to the floor)
#   Native Divide: right-click the tagged base edge, Divide, 2 segments. Native Weld: select the three edges
#   of `asg_run`, right-click, Weld Edges. Both are menu commands with no API; drive them with native
#   controls (context/NATIVE_CONTROL_CAPABILITIES.md) or by hand, then `EdgeSpike.scan`.
#   Run each case from `setup` in a new, empty Model (`setup` refuses a Model that already holds its
#   fixture); `:crossing` then `:heal` is the one two-step sequence.
require "json"

module EdgeSpike
  DICT = "phc_edge"
  REGISTRY = "phc_edge_registry"

  class << self
    def model
      Sketchup.active_model
    end

    def setup
      raise "EdgeSpike.setup needs an empty Model: this one already holds the B4 fixture." if container("zone")

      operation("B4 setup") do
        zone = box
        tag(zone.entities.grep(Sketchup::Edge).find { |e| south_bottom?(e) }, "asg_wall_base", "b4_type_base")
        tag(zone.entities.grep(Sketchup::Edge).find { |e| south_west_corner?(e) }, "asg_wall_corner", "b4_type_corner")
        runs = group("runs", [0, 6000.mm, 0])
        chain = [[0, 0, 0], [1000.mm, 0, 0], [2000.mm, 500.mm, 0], [3000.mm, 500.mm, 0]]
        chain.each_cons(2) { |a, b| tag(runs.entities.add_line(a, b), "asg_run", "b4_type_run") }
        loose = group("loose", [0, 9000.mm, 0])
        tag(loose.entities.add_line([0, 0, 0], [1500.mm, 0, 0]), "asg_loose_1", "b4_type_loose")
        tag(loose.entities.add_line([0, 500.mm, 0], [1500.mm, 500.mm, 0]), "asg_loose_2", "b4_type_loose")
        components
      end
      register
      scan
    end

    OPERATIONS = {
      :split => ->(s) { s.edge("asg_wall_base").split(0.5) },
      :weld => ->(s) { s.container("runs").entities.weld(s.edges("asg_run")) },
      :move => lambda { |s|
        lift = Geom::Transformation.new([0, 0, 300.mm])
        s.container("loose").entities.transform_entities(lift, s.edge("asg_loose_1"))
      },
      :pushpull => ->(s) { s.south_wall.pushpull(-200.mm) },
      :window_cut => ->(s) { s.place_window },
      :window_explode => ->(s) { s.window_unit.explode },
      # The cases B4 left open.
      :crossing => ->(s) { s.container("zone").entities.add_line([2500.mm, 0, 0], [2500.mm, 0, 1000.mm]) },
      :heal => ->(s) { s.container("zone").entities.erase_entities(s.crossing_edge || raise("run :crossing first")) },
      # Re-registers in the same operation, so one Undo restores the tag and the registry together and the
      # scan reads both halves under their own ids before the heal.
      :retag_half => lambda { |s|
        s.tag(s.east_half("asg_wall_base"), "asg_wall_base_b", "b4_type_base_b")
        s.write_registry
      },
      # The blade lives in its own Group so erasing it afterwards removes nothing of the box; only the
      # intersection edges stay, in the zone's own entities.
      :intersect => lambda { |s|
        zone = s.container("zone")
        blade = s.model.entities.add_group
        blade.entities.add_face([2500.mm, -500.mm, -500.mm], [2500.mm, 500.mm, -500.mm],
                                [2500.mm, 500.mm, 500.mm], [2500.mm, -500.mm, 500.mm])
        zone.entities.intersect_with(false, zone.transformation, zone.entities, zone.transformation, true, [blade])
        blade.erase!
      },
      :collapse => ->(s) { s.roof.pushpull(-3000.mm) }
    }.freeze

    def run(name)
      operation("B4 #{name}") { OPERATIONS.fetch(name).call(self) }
      scan
    end

    # Every tagged edge where it is now: persistent id, container path, world endpoints, length, tags.
    def snapshot
      found = []
      walk(model.entities, [], Geom::Transformation.new, found)
      found.sort_by { |e| [e["assignment_id"], e["path"], e["pid"]] }
    end

    # Classifies each registered assignment from a scan alone, with no observer.
    def scan
      now = snapshot
      registry = JSON.parse(model.get_attribute(REGISTRY, "assignments", "{}"))
      registry.to_h do |id, pids|
        found = now.select { |e| e["assignment_id"] == id }
        # The full dictionary travels with each edge, so a before-and-after comparison can show a merged or
        # partly kept record, not only that a tag is present.
        edges = found.map { |e| e.slice("pid", "path", "length_mm", "start", "end", "faces", "attributes") }
        targets = pids.map { |pid| target(pid, id) }
        [id, classify(pids, found).merge("edges" => edges, "registry_targets" => targets)]
      end
    end

    def edges(id, entities = nil)
      (entities || all_entities).grep(Sketchup::Edge).select { |e| e.get_attribute(DICT, "assignment_id") == id }
    end

    def edge(id)
      edges(id).first
    end

    def container(name)
      model.entities.grep(Sketchup::Group).find { |g| g.name == name }
    end

    def south_wall
      container("zone").entities.grep(Sketchup::Face).find { |f| f.normal.y < -0.99 }
    end

    def roof
      container("zone").entities.grep(Sketchup::Face).find { |f| f.normal.z > 0.99 }
    end

    # Of a split edge's halves, the one further along x.
    def east_half(id)
      edges(id).max_by { |e| e.start.position.x + e.end.position.x }
    end

    # The vertical line :crossing drew on the south wall, found by its own geometry (top at z = 1000 mm, which
    # no intersection edge shares) so a reopened Model still answers.
    def crossing_edge
      container("zone").entities.grep(Sketchup::Edge).find do |e|
        [e.start, e.end].all? { |v| (v.position.x - 2500.mm).abs < 0.001 && v.position.y.abs < 0.001 } &&
          ([e.start, e.end].map { |v| v.position.z }.max - 1000.mm).abs < 0.001
      end
    end

    # A B3 unit whose sill sits on the tagged base edge.
    def place_window
      zone = container("zone")
      definition = WindowSpike.define(1)
      wall = south_wall.vertices.first.position.y
      axes = Geom::Transformation.axes(Geom::Point3d.new(1000.mm, wall, 0), X_AXIS, Z_AXIS, Y_AXIS.reverse)
      unit = zone.entities.add_instance(definition, axes)
      unit.name = "b4_window"
      unit.glued_to = south_wall
    end

    def window_unit
      container("zone").entities.grep(Sketchup::ComponentInstance).find { |i| i.name == "b4_window" }
    end

    def tag(edge, assignment_id, type_id)
      edge.set_attribute(DICT, "type_id", type_id)
      edge.set_attribute(DICT, "assignment_id", assignment_id)
      edge.set_attribute(DICT, "payload", JSON.generate("example.ns" => { "note" => assignment_id, "rank" => 1 }))
      edge
    end

    def register
      operation("B4 register") { write_registry }
    end

    # The registry write alone, for a caller that already owns the operation.
    def write_registry
      grouped = snapshot.group_by { |e| e["assignment_id"] }
      assignments = grouped.transform_values { |list| list.map { |e| e["pid"] }.uniq }
      model.set_attribute(REGISTRY, "assignments", JSON.generate(assignments))
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

    def box
      zone = group("zone", [0, 0, 0])
      floor = zone.entities.add_face([0, 0, 0], [0, 4000.mm, 0], [5000.mm, 4000.mm, 0], [5000.mm, 0, 0])
      floor.reverse! if floor.normal.z.positive?
      floor.pushpull(-3000.mm)
      zone
    end

    def south_bottom?(edge)
      edge.start.position.y.abs < 0.001 && edge.end.position.y.abs < 0.001 &&
        edge.start.position.z.abs < 0.001 && edge.end.position.z.abs < 0.001
    end

    def south_west_corner?(edge)
      [edge.start, edge.end].all? { |v| v.position.x.abs < 0.001 && v.position.y.abs < 0.001 } &&
        [edge.start, edge.end].map { |v| v.position.z }.max > 1.mm
    end

    def group(name, origin)
      created = model.entities.add_group
      created.name = name
      created.transformation = Geom::Transformation.new(origin)
      created
    end

    # A two-edge run in one definition, placed twice inside a `systems` group: nested and repeated.
    def components
      definition = model.definitions.add("b4_pipe")
      a = definition.entities.add_line([0, 0, 0], [800.mm, 0, 0])
      b = definition.entities.add_line([800.mm, 0, 0], [800.mm, 600.mm, 0])
      tag(a, "asg_pipe", "b4_type_pipe")
      tag(b, "asg_pipe", "b4_type_pipe")
      systems = group("systems", [7000.mm, 6000.mm, 0])
      systems.entities.add_instance(definition, Geom::Transformation.new([0, 0, 0]))
      systems.entities.add_instance(definition, Geom::Transformation.new([0, 2000.mm, 0]))
    end

    def all_entities(entities = model.entities, found = [])
      entities.each do |entity|
        found << entity
        nested = entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        all_entities(entity.definition.entities, found) if nested
      end
      found.uniq
    end

    def walk(entities, path, transformation, found)
      entities.each do |entity|
        case entity
        when Sketchup::Edge then record(entity, path, transformation, found)
        when Sketchup::Group, Sketchup::ComponentInstance
          walk(entity.definition.entities, path + [entity.persistent_id], transformation * entity.transformation, found)
        end
      end
    end

    def record(edge, path, transformation, found)
      id = edge.get_attribute(DICT, "assignment_id")
      return unless id

      found << {
        "assignment_id" => id, "pid" => edge.persistent_id, "path" => path,
        "start" => edge.start.position.transform(transformation).to_a.map { |v| v.to_mm.round(1) },
        "end" => edge.end.position.transform(transformation).to_a.map { |v| v.to_mm.round(1) },
        "length_mm" => edge.length.to_mm.round(1), "faces" => edge.faces.length,
        "attributes" => edge.attribute_dictionary(DICT).to_h
      }
    end

    def classify(registered, found)
      pids = found.map { |e| e["pid"] }.uniq
      occurrences = found.map { |e| [e["pid"], e["path"]] }.uniq.length
      state =
        if found.empty? then "lost"
        elsif pids.sort == registered.sort
          occurrences > pids.length ? "kept, shared by #{occurrences} occurrences" : "kept"
        elsif (pids & registered).empty? then "replaced"
        else "split or extended"
        end
      { "state" => state, "registered" => registered.length, "edges_now" => pids.length,
        "total_length_mm" => found.uniq { |e| e["pid"] }.sum { |e| e["length_mm"] }.round(1),
        "attributes_intact" => found.all? { |e| e["attributes"]["assignment_id"] && e["attributes"]["payload"] } }
    end

    def target(pid, id)
      entity = model.find_entity_by_persistent_id(pid)
      return "missing" unless entity
      return "wrong kind #{entity.class}" unless entity.is_a?(Sketchup::Edge)

      entity.get_attribute(DICT, "assignment_id") == id ? "resolves" : "resolves to an edge without this assignment"
    end
  end
end
