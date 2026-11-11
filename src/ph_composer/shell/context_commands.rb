# frozen_string_literal: true

require_relative "pages"

module PhComposer
  # Where a Model session stands, as one read, and the two commands that move the edit path, registered
  # as a foundation capability (context/AGENT_INTERFACE.md, "Model context"). The read never moves the
  # edit path, the selection or the camera. `open` and `root` move the edit path through EditContext, so
  # every feature's boundary runs: leaving an open Volume, Spaces protects it, which both commands declare
  # in `side_effects`. They name no feature.
  #
  # A selection page is bound to the revision and the view generation it was read at, so a cursor
  # expires when the selection changes even though the Model did not. What is inside a container, with no
  # selection at all, is ContextChildren's read.
  module ContextCommands
    FEATURE_ID = "ph_composer.context"
    READ = "#{FEATURE_ID}.read"
    OPEN = "#{FEATURE_ID}.open"
    ROOT = "#{FEATURE_ID}.root"
    CHILDREN = "#{FEATURE_ID}.children"
    PATH = { "type" => "array", "items" => { "type" => "integer" },
             "description" => "Persistent ids of Groups and Components from the root, outermost first." }.freeze
    EXPECTED_PATH = PATH.merge("description" => "The edit path as last read; refused when it has changed since.")
    SIDE_EFFECTS = "Moves the edit path, which advances the Model revision. Leaving a Volume that was open and " \
                   "unprotected protects it again (Spaces locks it). No authored value changes; SketchUp itself " \
                   "records leaving a Group as an Undo entry, and undoing it reopens the Group."
    MOVE_REFUSES = %w[target.not_found target.locked target.wrong_kind target.shared_definition
                      target.edit_path_changed session.inactive].freeze
    # The tools during which the edit path may move: selecting and moving the camera hold no gesture.
    IDLE_TOOLS = %w[SelectionTool CameraOrbitTool CameraPanTool CameraZoomTool CameraZoomWindowTool].freeze
    MAXIMUM_LIMIT = 200
    LIMIT = { "type" => "integer", "minimum" => 1, "maximum" => MAXIMUM_LIMIT,
              "description" => "Selected entities per page, 1 to #{MAXIMUM_LIMIT}; #{Pages::DEFAULT_LIMIT} when " \
                               "absent. A page also stops before its rows pass #{Pages::MAX_PAGE_BYTES} bytes." }.freeze

    extend SchemaShapes

    module_function

    def install(registry)
      feature = registry.feature(FEATURE_ID, :contract_version => Declarations::CONTRACT_VERSION)
      install_navigation(feature)
      feature.query(READ, :description => "Where this Model session stands: the Model's file name and path, " \
                                          "its revision and view generation, whether it is busy and why, the " \
                                          "edit path from the root, and the selection in pages. Reads only.",
                          :params => object({ "limit" => LIMIT, "cursor" => Pages::CURSOR },
                                            :optional => %w[limit cursor]),
                          :result => result, :refuses => %w[query.cursor_expired query.limit_invalid],
                          :while_busy => true,
                          :examples => [{}, { "limit" => 50 }]) { |request| read(request) }
      ContextChildren.install(feature)
    end

    def install_navigation(feature)
      moved = object({ "path" => PATH, "changed" => { "type" => "boolean" } })
      terms = { :result => moved, :refuses => MOVE_REFUSES, :side_effects => SIDE_EFFECTS }
      feature.view_command(OPEN, **terms,
                           :description => "Open the Group or Component at the end of path as the edit context, " \
                                           "through every one above it. Refuses a locked or missing step.",
                           :params => object({ "path" => PATH, "expected_path" => EXPECTED_PATH },
                                             :optional => ["expected_path"]),
                           :examples => [{ "path" => [1201] },
                                         { "path" => [1201, 1202], "expected_path" => [] }]) do |request|
        move(request, request.params.fetch("path"))
      end
      feature.view_command(ROOT, **terms,
                           :description => "Close every open Group and Component, back to the Model's root.",
                           :params => object({ "expected_path" => EXPECTED_PATH }, :optional => ["expected_path"]),
                           :examples => [{}, { "expected_path" => [1201] }]) { |request| move(request, []) }
    end

    # Every refusal comes before EditContext runs a feature's boundary, which may write (Spaces protects a
    # Volume it leaves), so a refused move leaves the Model as it was. A path equal to the current one
    # changes nothing, whatever state its steps are in.
    def move(request, ids)
      model = request.model
      current = EditContext.current_ids(model)
      expected = request.params["expected_path"]
      if expected && expected != current
        raise CodedError.new("target.edit_path_changed", "The edit path changed since it was read; read " \
                                                         "ph_composer.context.read again.")
      end
      return { "path" => current, "changed" => false } if ids == current

      EditContext.shown!(model)
      tool_free!(model)
      path = resolve(model, ids)
      reentered!(EditContext.current(model), path)
      EditContext.enter(model, path)
      { "path" => EditContext.current_ids(model), "changed" => true }
    end

    # A definition open now and entered again on the destination through another occurrence (a copied
    # parent shares its children; a copied Volume shares its definition) would be left and entered at
    # once, so a boundary could lock what the move then opens, and SketchUp would refuse the path after
    # that write. The caller closes to the root first.
    def reentered!(current, path)
      ids = ->(entities) { entities.map(&:persistent_id) }
      path.each_with_index do |entity, depth|
        definition = entity.definition.persistent_id
        at = current.index { |open| open.definition.persistent_id == definition }
        next if at.nil? || ids.call(current[0..at]) == ids.call(path[0..depth])

        raise CodedError.new("target.shared_definition", "Group or Component #{entity.persistent_id} is open " \
                                                         "through another copy of its parent; close to the root " \
                                                         "first. Nothing moved.")
      end
    end

    # The refusal `open` would give `ids` now, from its own step checks, or nil when it would open them: a
    # read that offers a context to open says so before a client tries.
    def open_refusal(model, ids)
      resolve(model, ids)
      nil
    rescue CodedError => error
      error
    end

    def resolve(model, ids)
      entities = model.entities
      ids.map do |id|
        entity = entities.to_a.find { |candidate| container?(candidate) && candidate.persistent_id == id }
        raise CodedError.new("target.not_found", "No Group or Component #{id} is at that step.") unless entity
        raise CodedError.new("target.locked", "Group or Component #{id} is locked; nothing moved.") if entity.locked?
        if entity.definition.respond_to?(:live_component?) && entity.definition.live_component?
          raise CodedError.new("target.wrong_kind", "Component #{id} is a Live Component, which SketchUp does not " \
                                                    "open for editing; nothing moved.")
        end
        if entity.definition.instances.any?(&:locked?)
          raise CodedError.new("target.locked", "Another copy of Group or Component #{id} is locked, so SketchUp " \
                                                "cannot open it; nothing moved.")
        end

        entities = entity.definition.entities
        entity
      end
    end

    # A user's tool other than Select or a camera tool may hold a gesture that a path change would end, so
    # the move waits for the user rather than closing it.
    def tool_free!(model)
      tools = model.respond_to?(:tools) ? model.tools : nil
      name = tools.respond_to?(:active_tool_name) ? tools.active_tool_name.to_s : ""
      return if name.empty? || IDLE_TOOLS.include?(name)

      raise CodedError.new("session.busy", "The #{name} tool is in use in SketchUp; the edit path moves once the " \
                                           "user returns to Select. Nothing moved.")
    end

    def container?(entity)
      entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    end

    def read(request)
      session = request.session
      model = session.model
      rows = model.selection.to_a.map { |entity| entity_row(entity) }.sort_by { |row| row["persistent_id"] }
      # A cursor position is a String or an Array (shell/pages.rb), so the id travels in one.
      page, next_cursor = Pages.bounded(request, READ, rows, :key => ->(row) { [row["persistent_id"]] },
                                                             :revision => [session.revision, session.view_generation])
      { "session" => { "id" => session.id, "file_name" => File.basename(model.path.to_s), "path" => model.path.to_s,
                       "revision" => session.revision, "view_generation" => session.view_generation,
                       "active" => model.equal?(Sketchup.active_model) },
        "readiness" => readiness(session, model),
        "edit_path" => Array(model.active_path).map { |instance| entity_row(instance) },
        "camera" => camera(model),
        "selection" => { "count" => rows.length, "entities" => page, "next_cursor" => next_cursor } }
    end

    # Whether a change could start now: not while another runs or deferred work waits, or while the user is
    # partway through a gesture a commit would cancel; and the tool the user has active, which some commands
    # also refuse during.
    def readiness(session, model)
      reason = session.busy_reason || session.gesture_reason
      tools = model.respond_to?(:tools) ? model.tools : nil
      { "busy" => !reason.nil?, "reason" => reason,
        "active_tool" => tools.respond_to?(:active_tool_name) ? tools.active_tool_name.to_s : nil }
    end

    # One entity as the context names it: its persistent id, its SketchUp type and its name, if any.
    # Where the view looks from, in metres in model space, as SketchUp's camera says it. Reading it moves
    # nothing; a camera change advances the view generation (HostObservers::ViewObserver).
    def camera(model)
      view = model.respond_to?(:active_view) ? model.active_view : nil
      camera = view&.camera
      return nil unless camera.respond_to?(:target)

      metres = ->(point) { [point.x, point.y, point.z].map { |value| value.to_f * FaceGeometry::INCH_TO_M } }
      perspective = camera.perspective?
      { "eye_m" => metres.call(camera.eye), "target_m" => metres.call(camera.target),
        "up" => [camera.up.x, camera.up.y, camera.up.z].map(&:to_f), "perspective" => perspective,
        "fov_deg" => perspective ? camera.fov.to_f : nil,
        "fov_axis" => perspective ? fov_axis(camera) : nil,
        "two_point" => two_point(camera),
        "height_m" => perspective ? nil : camera.height.to_f * FaceGeometry::INCH_TO_M }
    end

    # Which extent of the view the field of view spans: SketchUp keeps it for the height unless set
    # otherwise.
    def fov_axis(camera)
      !camera.respond_to?(:fov_is_height?) || camera.fov_is_height? ? "height" : "width"
    end

    # Two-point perspective frames the view by a pan offset and a scale on top of the camera; null when the
    # camera is an ordinary one.
    def two_point(camera)
      return nil unless camera.respond_to?(:is_2d?) && camera.is_2d?

      center = camera.center_2d
      { "center" => [center.x.to_f, center.y.to_f], "scale" => camera.scale_2d.to_f }
    end

    def entity_row(entity)
      name = entity.respond_to?(:name) ? entity.name.to_s : ""
      definition = entity.respond_to?(:definition) ? entity.definition : nil
      name = definition.name.to_s if name.empty? && definition.respond_to?(:name)
      { "persistent_id" => entity.persistent_id, "type" => entity.typename, "name" => name }
    end

    def entity
      object({ "persistent_id" => { "type" => "integer", "description" => "The entity's persistent id." },
               "type" => { "type" => "string", "description" => "SketchUp's type name, such as Group or Face." },
               "name" => { "type" => "string", "description" => "The instance or definition name; empty if none." } })
    end

    def session_shape
      generation = { "type" => "integer", "description" => "Advances when the selection or the camera changes, " \
                                                           "without a revision." }
      object({ "id" => { "type" => "string" }, "file_name" => { "type" => "string" },
               "path" => { "type" => "string", "description" => "The Model's file path; empty until it is saved." },
               "revision" => { "type" => "integer" }, "view_generation" => generation,
               "active" => { "type" => "boolean" } })
    end

    def readiness_shape
      tool = { "type" => %w[string null], "description" => "The SketchUp tool the user has active." }
      object({ "busy" => { "type" => "boolean" }, "reason" => { "type" => %w[string null] }, "active_tool" => tool })
    end

    def selection_shape
      object({ "count" => { "type" => "integer", "minimum" => 0 },
               "entities" => list(entity, :description => "This page, by persistent id."),
               "next_cursor" => Pages::NEXT_CURSOR })
    end

    def result
      path = list(entity, :description => "The open Groups and Components from the root, outermost first; empty " \
                                          "at the root.")
      object({ "session" => session_shape, "readiness" => readiness_shape, "edit_path" => path,
               "camera" => camera_shape, "selection" => selection_shape })
    end

    def camera_shape
      point = { "type" => "array", "items" => { "type" => "number" }, "x-unit" => "m" }
      object({ "eye_m" => point, "target_m" => point,
               "up" => { "type" => "array", "items" => { "type" => "number" } },
               "perspective" => { "type" => "boolean" },
               "fov_deg" => { "type" => %w[number null], "description" => "Field of view; null for a parallel view." },
               "fov_axis" => { "type" => %w[string null], "enum" => ["height", "width", nil],
                               "description" => "The view extent fov_deg spans; null for a parallel view." },
               "two_point" => { "type" => %w[object null],
                                "description" => "Two-point perspective's pan offset (center, in the view's own " \
                                                 "units) and scale; null for an ordinary camera." },
               "height_m" => { "type" => %w[number null], "x-unit" => "m",
                               "description" => "The view's height; null for a perspective view." } }).merge(
                                 "type" => %w[object null], "description" => "The view's camera; null with no view."
                               )
    end
  end
end
