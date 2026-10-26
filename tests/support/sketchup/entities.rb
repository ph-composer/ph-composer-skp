# frozen_string_literal: true

# Sketchup entity classes: observers, attribute dictionaries, faces, edges, entities
# collections, component definitions and instances, groups and the selection.

module Sketchup
  module RegionalSettings
    class << self
      attr_writer :decimal_separator

      def decimal_separator
        @decimal_separator || "."
      end

      def reset
        @decimal_separator = nil
      end
    end
  end

  class InputPoint
    attr_reader :position, :face, :tooltip, :draw_count

    def initialize
      @valid = false
      @draw_count = 0
    end

    def pick(view, _x, _y)
      value = view.pick_result || {}
      @valid = value.fetch(:valid, false)
      @position = value[:position]
      @face = value[:face]
      @tooltip = value.fetch(:tooltip, "")
      @valid
    end

    def valid?
      @valid
    end

    def display?
      @valid
    end

    def draw(_view)
      @draw_count += 1
    end
  end

  class AppObserver; end
  class ModelObserver; end
  class EntityObserver; end
  class EntitiesObserver; end
  class SelectionObserver; end
  class ViewObserver; end
  class PagesObserver; end
  class LayersObserver; end

  class Color
    attr_reader :red, :green, :blue, :alpha

    def initialize(red, green, blue, alpha = 255)
      @red, @green, @blue, @alpha = red, green, blue, alpha
    end

    def to_a
      [@red, @green, @blue, @alpha]
    end
  end

  class Overlay
    attr_reader :overlay_id, :name, :description

    def initialize(id, name, description: "")
      @overlay_id, @name, @description = id, name, description
      @valid = true
      # A new overlay is disabled, as the host's is: `OverlaysManager#add` accepts it, shows it
      # unticked in the Overlays panel and never calls `draw` until something enables it. Measured
      # on 26.1.188, 2026-09-20, when a Colour-by mode turned on drew nothing at all.
      @enabled = false
    end

    def valid?
      @valid
    end

    def invalidate
      @valid = false
    end

    def enabled?
      @enabled
    end

    attr_writer :enabled
  end

  class ObservableCollection
    attr_reader :observers

    def initialize
      @observers = []
    end

    def add_observer(observer)
      @observers << observer
      true
    end

    def remove_observer(observer)
      @observers.delete(observer)
      true
    end
  end

  # SketchUp's tag collection. It knows its Model, so an observer can reach the session.
  class Layers < ObservableCollection
    attr_reader :model

    def initialize(model)
      super()
      @model = model
    end
  end

  class OverlaysManager
    include Enumerable

    def initialize
      @values = []
    end

    def add(overlay)
      return false if @values.any? { |value| value.overlay_id == overlay.overlay_id }

      @values << overlay
      overlay.start if overlay.respond_to?(:start)
      true
    end

    def remove(overlay)
      return false unless @values.delete(overlay)

      overlay.invalidate
      true
    end

    def each(&block)
      @values.each(&block)
    end

    def include?(overlay)
      @values.include?(overlay)
    end

    def empty?
      @values.empty?
    end
  end

  # The host picks whatever is under the pointer; the stub picks whatever a fixture put at those
  # coordinates. `picks` maps [x, y] to one root-to-leaf entity path, or to several when a test
  # means to check that the best Face wins over a nearer Edge.
  class PickHelper
    def initialize(view)
      @view = view
      @paths = []
    end

    def do_pick(x_value, y_value)
      found = @view.picks[[x_value, y_value]]
      @paths = found.nil? ? [] : (found.first.is_a?(Array) ? found : [found])
      @paths.length
    end

    def count
      @paths.length
    end

    def path_at(index)
      @paths[index]
    end

    def leaf_at(index)
      @paths[index]&.last
    end
  end

  # The host's Camera, with the stub's defaults: looking down from the eye, perspective, 35 degrees.
  Camera = Struct.new(:eye, :target, :up, :perspective, :fov, :height) do
    def initialize(eye, target = nil, up = nil, perspective = true, fov = 35.0, height = 0.0)
      super(eye, target || Geom::Point3d.new(eye.x, eye.y, 0), up || Geom::Vector3d.new(0, 1, 0), perspective, fov,
            height)
    end

    def perspective?
      perspective
    end

    def fov_is_height?
      !@fov_is_width
    end

    attr_writer :fov_is_width
    attr_accessor :two_point_center, :two_point_scale

    def is_2d?
      !two_point_center.nil?
    end

    def center_2d
      Geom::Point3d.new(*two_point_center, 0)
    end

    def scale_2d
      two_point_scale
    end
  end

  class View
    attr_accessor :line_width, :drawing_color, :pick_result, :line_stipple, :tooltip
    attr_accessor :model_units_per_pixel
    attr_reader :camera
    attr_reader :model, :draws, :screen_draws, :texts, :invalidations, :zoomed, :picks

    def initialize(model)
      @model = model
      @draws = []
      @screen_draws = []
      @texts = []
      @invalidations = 0
      @zoomed = []
      @picks = {}
      # Far enough above the fixtures that a lift toward it is a clean +z, and one model unit a
      # pixel, so a test can state the lift it expects.
      @camera = Camera.new(Geom::Point3d.new(0, 0, 1_000_000))
      @model_units_per_pixel = 1.0
    end

    # The viewport's size in pixels, and the images write_image wrote: a small placeholder file whose bytes
    # name the size asked for. The host renders the Model's geometry; nothing here draws.
    def vpwidth
      1600
    end

    def vpheight
      1000
    end

    # A test sets `write_image_hook` to stand in for what the host does while writing: answer false, write
    # other bytes, or move the view.
    attr_accessor :write_image_hook

    def write_image(options)
      (@images ||= []) << options
      return write_image_hook.call(options) if write_image_hook

      File.binwrite(options.fetch(:filename), "\x89PNG\r\n\x1A\n#{options[:width]}x#{options[:height]}".b)
      true
    end

    def images
      @images || []
    end

    # A camera change notifies the view's observers, as the host's onViewChanged does.
    def camera=(camera)
      @camera = camera
      (@observers || []).each { |observer| observer.onViewChanged(self) if observer.respond_to?(:onViewChanged) }
    end

    def add_observer(observer)
      (@observers ||= []) << observer
      true
    end

    def remove_observer(observer)
      (@observers || []).delete(observer)
      true
    end

    def pixels_to_model(pixels, _point)
      pixels * @model_units_per_pixel
    end

    def pick_helper
      @pick_helper ||= PickHelper.new(self)
    end

    def draw(mode, points)
      @draws << [mode, points.dup, @drawing_color, @line_width]
    end

    def draw2d(mode, points)
      @screen_draws << [mode, points.dup, @drawing_color]
    end

    def draw_text(point, text, options = {})
      @texts << [point, text, options]
    end

    def invalidate
      @invalidations += 1
      self
    end

    def zoom(entity)
      @zoomed << entity
    end
  end

  # `folder` is the LayerFolder holding the tag, nil at the top level, as on the host since SketchUp 2021.
  Tag = Struct.new(:name, :visible, :folder) do
    def visible?
      visible != false
    end
  end

  # A tag folder: hidden, it hides every tag inside it and inside the folders it holds.
  LayerFolder = Struct.new(:name, :visible, :folder) do
    def visible?
      visible != false
    end
  end

  # A host Vertex has a persistent id. Here it is allocated on first read from its own sequence, so
  # vertices never shift the ids tests expect other entities to receive.
  class Vertex
    attr_reader :position

    class << self
      def allocate_persistent_id
        @next_persistent_id = (@next_persistent_id || 500_000_000) + 1
      end
    end

    def initialize(position)
      @position = position
    end

    def persistent_id
      @persistent_id ||= self.class.allocate_persistent_id
    end

    def transform!(transformation)
      @position = @position.transform(transformation)
    end
  end

  class Loop
    attr_reader :vertices

    def initialize(points)
      @vertices = points.map { |point| Vertex.new(point) }
    end

    def transform!(transformation)
      @vertices.each { |vertex| vertex.transform!(transformation) }
    end

    def reverse!
      @vertices.reverse!
    end
  end

  class AttributeDictionary
    include Enumerable

    attr_reader :name

    def initialize(name, values = {})
      @name = name
      @values = values.dup
    end

    def [](key)
      @values[key]
    end

    def []=(key, value)
      @values[key] = value
    end

    def delete_key(key)
      @values.delete(key)
    end

    def empty?
      @values.empty?
    end

    def each(&block)
      @values.each(&block)
    end
  end

  class Entity
    attr_reader :persistent_id
    attr_accessor :layer, :parent_entities
    attr_writer :hidden

    # The host's type name: "Group", "Face", "ComponentInstance".
    def typename
      self.class.name.split("::").last
    end

    def initialize(persistent_id, dictionaries = {})
      @persistent_id = persistent_id
      @hidden = false
      @dictionaries = dictionaries.each_with_object({}) do |(name, values), result|
        result[name] = AttributeDictionary.new(name, values)
      end
      @layer = Tag.new("Untagged", true)
    end

    def hidden?
      @hidden
    end

    def add_observer(observer)
      (@observers ||= []) << observer
      true
    end

    def remove_observer(observer)
      (@observers ||= []).delete(observer)
      true
    end

    # Native observers do not persist in SKP/Undo state. Marshal models those boundaries here.
    def marshal_dump
      instance_variables.reject { |key| key == :@observers }.to_h { |key| [key, instance_variable_get(key)] }
    end

    def marshal_load(values)
      values.each { |key, value| instance_variable_set(key, value) }
      @observers = []
    end

    def attribute_dictionaries
      @dictionaries.values unless @dictionaries.empty?
    end

    def attribute_dictionary(name)
      @dictionaries[name]
    end

    def get_attribute(dictionary_name, key, default = nil)
      dictionary = @dictionaries[dictionary_name]
      dictionary ? (dictionary[key].nil? ? default : dictionary[key]) : default
    end

    def set_attribute(dictionary_name, key, value)
      dictionary = (@dictionaries[dictionary_name] ||= AttributeDictionary.new(dictionary_name))
      dictionary[key] = value
      value
    end

    def delete_attribute(dictionary_name, key = nil)
      if key
        dictionary = @dictionaries[dictionary_name]
        return nil unless dictionary

        value = dictionary.delete_key(key)
        @dictionaries.delete(dictionary_name) if dictionary.empty?
        value
      else
        @dictionaries.delete(dictionary_name)
      end
    end

    def entityID
      @persistent_id
    end
  end

  # The host's base for everything an entities collection holds: Faces, Edges, Groups, instances. An
  # Entity that is not one, as a test plants to stand for a non-geometric child, is not.
  class Drawingelement < Entity; end

  class Face < Drawingelement
    attr_reader :loops, :outer_loop, :normal, :edges
    attr_accessor :material, :back_material

    # `edges` is opt-in. The host always gives a Face its bounding Edges, but most fixtures here do
    # not care about topology, so a Face built without them simply reports none and any rule that
    # reads topology is vacuously satisfied. A fixture that means to test edge sharing passes them.
    def initialize(persistent_id, dictionaries = {}, points: nil, holes: [], normal: nil, edges: [])
      super(persistent_id, dictionaries)
      points ||= [Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(1, 0, 0), Geom::Point3d.new(1, 1, 0)]
      @outer_loop = Loop.new(points)
      @loops = [@outer_loop] + holes.map { |loop| Loop.new(loop) }
      @normal = normal || Face.newell_normal(@outer_loop.vertices.map(&:position))
      @edges = Array(edges)
      @edges.each { |edge| edge.attach_face(self) }
    end

    # Every vertex of every loop, as the host's `Face#vertices` lists them.
    def vertices
      @loops.flat_map(&:vertices).uniq
    end

    # Membership and glue only: the stub does not simulate native opening-cut geometry.
    def get_glued_instances
      return [] unless parent_entities

      parent_entities.to_a.grep(ComponentInstance).select { |instance| instance.glued_to.equal?(self) }
    end

    # The host derives a Face's normal from its winding. A fixture that says nothing about the
    # normal gets the one its own points imply, so a Face built by add_face faces the right way.
    def self.newell_normal(points)
      vector = points.each_with_index.reduce([0.0, 0.0, 0.0]) do |sum, (point, index)|
        following = points[(index + 1) % points.length]
        [sum[0] + ((point.y - following.y) * (point.z + following.z)),
         sum[1] + ((point.z - following.z) * (point.x + following.x)),
         sum[2] + ((point.x - following.x) * (point.y + following.y))]
      end
      length = Math.sqrt(vector.sum { |value| value**2 })
      return Geom::Vector3d.new(0, 0, 1) if length < 1.0e-12

      Geom::Vector3d.new(*vector.map { |value| value / length })
    end

    # As the host does, a Face's area is its outline less its holes.
    def area(transformation = Geom::Transformation.new)
      @loops.each_with_index.sum do |loop, index|
        value = loop_area(loop, transformation)
        index.zero? ? value : -value
      end
    end

    def loop_area(loop, transformation)
      points = loop.vertices.map { |vertex| vertex.position.transform(transformation) }
      vector = points.each_with_index.reduce([0.0, 0.0, 0.0]) do |sum, (point, index)|
        following = points[(index + 1) % points.length]
        [
          sum[0] + (point.y - following.y) * (point.z + following.z),
          sum[1] + (point.z - following.z) * (point.x + following.x),
          sum[2] + (point.x - following.x) * (point.y + following.y)
        ]
      end
      Math.sqrt(vector.sum { |value| value**2 }) / 2.0
    end
    private :loop_area

    def transform!(transformation)
      @loops.each { |loop| loop.transform!(transformation) }
    end

    # The host reverses the loop winding and the normal together and keeps every attribute
    # dictionary on the Face. Nothing else about the Face changes.
    def reverse!
      @loops.each(&:reverse!)
      @normal = Geom::Vector3d.new(-@normal.x, -@normal.y, -@normal.z)
      true
    end

    # Used by the split model: the host reshapes a Face in place, keeping its identity and every
    # attribute dictionary on it.
    def replace_outline!(points)
      @outer_loop = Loop.new(points)
      @loops[0] = @outer_loop
      self
    end

    def add_hole!(points)
      @loops << Loop.new(points)
      self
    end

    # The host triangulates a Face, holes and concavity included, and hands back a PolygonMesh. This
    # stub fans the outer loop instead, which is only right for a convex outline: it exists so the
    # Colour-by cache can be tested for what it batches and counts, never as evidence about how
    # SketchUp tessellates. See tests/sketchup_stub_deviations_test.rb.
    def mesh(_flags = 0)
      PolygonMesh.new(@outer_loop.vertices.map(&:position))
    end
  end

  # A fan over the points it was given: 1-based indices, as the host's PolygonMesh uses.
  class PolygonMesh
    attr_reader :points

    def initialize(points)
      @points = points
    end

    def polygons
      (1..(@points.length - 2)).map { |index| [1, index + 1, index + 2] }
    end

    def count_polygons
      polygons.length
    end

    def point_at(index)
      @points[index - 1]
    end
  end

  class Edge < Drawingelement
    attr_reader :start, :end, :faces

    def initialize(persistent_id, start_point, end_point, dictionaries = {})
      super(persistent_id, dictionaries)
      # A Vertex passed in is shared, as two host Edges meeting at a point share one.
      @start = start_point.is_a?(Vertex) ? start_point : Vertex.new(start_point)
      @end = end_point.is_a?(Vertex) ? end_point : Vertex.new(end_point)
      @faces = []
    end

    def attach_face(face)
      @faces << face unless @faces.include?(face)
    end

    def transform!(transformation)
      @start.transform!(transformation)
      @end.transform!(transformation)
    end
  end

  class Entities
    include Enumerable

    @next_persistent_id = 100_000

    class << self
      attr_accessor :next_persistent_id

      def allocate_persistent_id
        self.next_persistent_id ||= 100_000
        self.next_persistent_id += 1
      end
    end

    attr_accessor :root
    attr_reader :each_count, :scan_count

    # The Groups drawn from this collection. A Group registers itself when it is built on one.
    def group_instances
      @group_instances ||= []
    end

    def register_group(group)
      @group_definition_id ||= self.class.allocate_persistent_id
      group_instances << group unless group_instances.include?(group)
    end

    def group_definition_id
      @group_definition_id
    end

    def initialize(values = [])
      @values = []
      @observers = []
      @root = false
      @each_count = 0
      @scan_count = 0
      values.each { |entity| self << entity }
    end

    # Collection observers, like entity observers, are live attachments rather than saved data.
    def marshal_dump
      instance_variables.reject { |key| key == :@observers }.to_h { |key| [key, instance_variable_get(key)] }
    end

    def marshal_load(values)
      values.each { |key, value| instance_variable_set(key, value) }
      @observers = []
    end

    def each(&block)
      @each_count += 1 if @root
      @values.each(&block)
    end

    def to_a
      @values.dup
    end

    def length
      @values.length
    end

    def [](index)
      # ModelWalker begins each root traversal at index zero instead of Enumerable#each.
      @scan_count += 1 if @root && index.zero?
      @values[index]
    end

    # An erased Group is no longer an instance of its definition (measured on 26.1.188, 2026-10-15:
    # context/SKETCHUP_HOST_BEHAVIOR.md, "Re-placing a Group's definition").
    def delete(entity)
      deleted = @values.delete(entity)
      entity.parent_entities = nil if deleted && entity.respond_to?(:parent_entities=)
      entity.entities.group_instances.delete(entity) if deleted && entity.is_a?(Group)
      deleted
    end

    def <<(entity)
      entity.parent_entities.delete(entity) if entity.respond_to?(:parent_entities) && entity.parent_entities &&
                                               !entity.parent_entities.equal?(self)
      entity.parent_entities = self if entity.respond_to?(:parent_entities=)
      @values << entity
      @observers.each { |observer| observer.onElementAdded(self, entity) if observer.respond_to?(:onElementAdded) }
      self
    end

    def include?(entity)
      @values.include?(entity)
    end

    def add_group(entities = [])
      members = Array(entities)
      unless members.all? { |entity| include?(entity) }
        raise ArgumentError, "all grouped entities must belong to this collection"
      end

      members.each { |entity| delete(entity) }
      group = Group.new(self.class.allocate_persistent_id, Entities.new(members))
      self << group
      group
    end

    # A model of how the host splits a Face, not evidence about it. Drawing an outline onto a
    # coplanar Face that contains it leaves the shared region as a new Face and the original Face
    # holding what is left: its outline shrinks when the region touches its boundary, and it gains
    # a hole when the region sits wholly inside it, which is what SketchUp does. The original keeps
    # its persistent id here; on the host that is measured, not assumed, which is why the caller
    # looks the survivor up rather than relying on it.
    def add_face(points)
      face = Face.new(self.class.allocate_persistent_id, {}, :points => Array(points))
      host = to_a.grep(Face).find { |candidate| PhComposerStub.splittable?(candidate, face) }
      PhComposerStub.split!(host, face) if host
      self << face
      face
    end

    # A Group's definition places a new Group over the same entities, carrying none of the original's
    # instance dictionaries or name (measured on 26.1.188, 2026-10-15: context/SKETCHUP_HOST_BEHAVIOR.md,
    # "Re-placing a Group's definition").
    def add_instance(definition, transformation)
      persistent_id = self.class.allocate_persistent_id
      if definition.is_a?(GroupDefinition)
        group = Group.new(persistent_id, definition.entities, {}, :transformation => transformation)
        self << group
        return group
      end

      instance = ComponentInstance.new(persistent_id, definition, {}, :transformation => transformation)
      self << instance
      instance
    end

    def erase_entities(*entities)
      entities.flatten.each { |entity| delete(entity) }
      true
    end

    def clear!
      erase_entities(to_a)
    end

    def transform_entities(transformation, entities)
      Array(entities).each { |entity| entity.transform!(transformation) if entity.respond_to?(:transform!) }
      true
    end

    def add_observer(observer)
      @observers << observer
      true
    end

    def remove_observer(observer)
      @observers.delete(observer)
      true
    end
  end

  class Behavior
    attr_writer :cuts_opening, :is2d, :no_scale_mask
    attr_accessor :snapto

    def cuts_opening?
      @cuts_opening == true
    end

    def is2d?
      @is2d == true
    end

    def no_scale_mask?
      @no_scale_mask || 0
    end
  end

  class ComponentDefinition
    attr_reader :entities, :guid, :persistent_id, :behavior
    attr_accessor :name

    def initialize(entities = Entities.new, guid: nil, name: "Definition", dictionaries: {})
      @entities = entities
      @guid = guid || "definition-#{object_id}"
      @behavior = Behavior.new
      @persistent_id = Entities.allocate_persistent_id
      @name = name
      @dictionaries = dictionaries.each_with_object({}) do |(dictionary_name, values), result|
        result[dictionary_name] = AttributeDictionary.new(dictionary_name, values)
      end
    end

    def attribute_dictionary(name)
      @dictionaries[name]
    end

    # Fixtures select their owning Model as active. Enumerate storage, including unused
    # definitions, once so copied parent occurrences do not duplicate native instances.
    def instances
      model = Sketchup.active_model
      return [] unless model

      pending = [model.entities] + model.definitions.map(&:entities)
      visited = {}
      result = []
      until pending.empty?
        entities = pending.shift
        next if visited[entities.object_id]

        visited[entities.object_id] = true
        entities.each do |entity|
          if entity.is_a?(ComponentInstance)
            result << entity if entity.definition.equal?(self)
            pending << entity.definition.entities
          elsif entity.is_a?(Group)
            pending << entity.entities
          end
        end
      end
      result
    end

    def attribute_dictionaries
      @dictionaries.values unless @dictionaries.empty?
    end

    def get_attribute(dictionary_name, key, default = nil)
      dictionary = @dictionaries[dictionary_name]
      dictionary ? (dictionary[key].nil? ? default : dictionary[key]) : default
    end

    def set_attribute(dictionary_name, key, value)
      dictionary = (@dictionaries[dictionary_name] ||= AttributeDictionary.new(dictionary_name))
      dictionary[key] = value
      value
    end
  end

  # The host's `volume` (cubic inches), as measured (context/SKETCHUP_HOST_BEHAVIOR.md, "Solid volume"): a
  # solid's volume scaled by the placement's own transform and no parent's, and negative when the container is
  # not a solid. A fixture states the unscaled solid volume with `solid_volume=`.
  module SolidVolume
    attr_writer :solid_volume

    def volume
      return -1.0 unless @solid_volume

      m = transformation.to_a
      determinant = (m[0] * ((m[5] * m[10]) - (m[9] * m[6]))) - (m[4] * ((m[1] * m[10]) - (m[9] * m[2]))) +
                    (m[8] * ((m[1] * m[6]) - (m[5] * m[2])))
      @solid_volume * determinant.abs
    end
  end

  class ComponentInstance < Drawingelement
    include SolidVolume

    attr_accessor :definition
    attr_accessor :transformation, :name, :glued_to

    def locked?
      !!@locked
    end

    def locked=(value)
      @locked = !!value
    end

    def initialize(persistent_id, definition, dictionaries = {}, transformation: nil, name: "", glued_to: nil)
      super(persistent_id, dictionaries)
      @definition = definition
      @transformation = transformation || Geom::Transformation.new
      @name = name
      @glued_to = glued_to
    end

    def make_unique
      @definition = Marshal.load(Marshal.dump(@definition))
      self
    end
  end

  # What a Group's contents are, and which Groups are drawn from them. The host models this as a
  # ComponentDefinition with instances; here it is derived from the Entities collection, so two
  # Groups built on one collection report each other exactly as two copies do on the host.
  class GroupDefinition
    attr_reader :entities, :behavior

    def initialize(entities)
      @entities = entities
      @behavior = Behavior.new
    end

    def instances
      @entities.group_instances
    end

    def persistent_id
      @entities.group_definition_id
    end
  end

  class Group < Drawingelement
    include SolidVolume

    attr_reader :entities
    attr_accessor :transformation
    attr_reader :name

    def initialize(persistent_id, entities = Entities.new, dictionaries = {},
                   transformation: nil, name: "", locked: false)
      super(persistent_id, dictionaries)
      @entities = entities
      @transformation = transformation || Geom::Transformation.new
      @name = name
      @locked = locked
      @entities.register_group(self) if @entities.respond_to?(:register_group)
    end

    def locked?
      @locked
    end

    # This delivers a property notification only; native transaction timing and Undo callbacks
    # must be measured on the host, not inferred from the setter used by offline tests.
    def name=(value)
      @name = value
      (@observers ||= []).each do |observer|
        observer.onChangeEntity(self) if observer.respond_to?(:onChangeEntity)
      end
      value
    end

    def locked=(value)
      @locked = !!value
    end

    # Copying a Group on the host makes both Groups instances of one definition, sharing every
    # entity in it. A fixture models that by giving two Groups the same Entities collection; the
    # definition each reports then knows both of them.
    def definition
      GroupDefinition.new(@entities)
    end

    # Measured on 26.1.188, 2026-10-12, on copied Zones: Make Unique gives this placement a
    # new definition whose Faces are new entities carrying copies of the shared Faces' dictionaries.
    # The other placement keeps its definition and entities. A nested Group becomes a new placement
    # of its own definition, so it stays shared until it is made unique in turn.
    # Every member becomes a new entity with a new persistent id and copied dictionaries. A Component
    # Instance keeps its definition and transform and is glued to the new copy of its glued Face
    # (measured, context/SKETCHUP_HOST_BEHAVIOR.md, "Window Units inside a copied Zone").
    def make_unique
      return self unless definition.instances.length > 1

      copies = {}.compare_by_identity
      @entities.to_a.each { |entity| copies[entity] = unique_member(entity) }
      copies.each_value do |copy|
        copy.glued_to = copies.fetch(copy.glued_to, copy.glued_to) if copy.is_a?(ComponentInstance) && copy.glued_to
      end
      members = copies.values
      @entities.group_instances.delete(self)
      @entities = Entities.new(members)
      @entities.register_group(self)
      self
    end

    def explode
      raise ArgumentError, "group has no parent entities" unless parent_entities

      destination = parent_entities
      members = @entities.to_a
      destination.delete(self)
      members.each do |entity|
        if entity.respond_to?(:transformation) && entity.respond_to?(:transformation=)
          entity.transformation = @transformation * entity.transformation
        elsif entity.respond_to?(:transform!)
          entity.transform!(@transformation)
        end
        destination << entity
      end
      members
    end

    private

    def unique_member(entity)
      dictionaries = Marshal.load(Marshal.dump(
        (entity.attribute_dictionaries || []).to_h { |dictionary| [dictionary.name, dictionary.to_h] }
      ))
      id = Entities.allocate_persistent_id
      case entity
      when Face
        Face.new(id, dictionaries, :points => entity.outer_loop.vertices.map(&:position), :normal => entity.normal)
      when Group
        Group.new(id, entity.entities, dictionaries, :transformation => entity.transformation, :name => entity.name,
                                                     :locked => entity.locked?)
      when ComponentInstance
        ComponentInstance.new(id, entity.definition, dictionaries, :transformation => entity.transformation,
                                                                   :name => entity.name, :glued_to => entity.glued_to)
                         .tap { |copy| copy.locked = entity.locked? }
      else
        entity
      end
    end
  end

  class Selection
    include Enumerable

    attr_reader :observers

    def initialize(model = nil)
      @model = model
      @values = []
      @observers = []
    end

    def each(&block)
      @values.each(&block)
    end

    def to_a
      @values.dup
    end

    def add(values)
      candidates = Array(values)
      changed = false
      candidates.each do |value|
        next if @model && !Array(@model.active_path).empty? && !@model.active_entities.include?(value)
        next if @values.include?(value)

        @values << value
        changed = true
        @observers.each do |observer|
          observer.onSelectionAdded(self, value) if observer.respond_to?(:onSelectionAdded)
        end
      end
      if changed && candidates.length > 1
        @observers.each do |observer|
          observer.onSelectionBulkChange(self) if observer.respond_to?(:onSelectionBulkChange)
        end
      end
      self
    end

    def clear
      changed = @values.any?
      @values.clear
      if changed
        @observers.each do |observer|
          observer.onSelectionCleared(self) if observer.respond_to?(:onSelectionCleared)
        end
      end
      self
    end

    def remove(value)
      removed = @values.delete(value)
      if removed
        @observers.each do |observer|
          observer.onSelectionRemoved(self, value) if observer.respond_to?(:onSelectionRemoved)
        end
      end
      removed
    end

    def add_observer(observer)
      @observers << observer
      true
    end

    def remove_observer(observer)
      @observers.delete(observer)
      true
    end
  end
end
