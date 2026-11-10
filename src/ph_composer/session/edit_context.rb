# frozen_string_literal: true

module PhComposer
  # The one place the extension assigns `model.active_path` (context/TECH_STACK.md, "Treat the active
  # editing path as data"); a test refuses any other assignment. Every change of path first runs each
  # registered boundary with the path being left and the path being entered, so a feature that keeps
  # something open in an edit context (a Volume) protects it before the context moves. It names no
  # feature: a feature registers its boundary in its `install`.
  module EditContext
    module_function

    def current(model)
      Array(model.active_path)
    end

    # The persistent-id path of the open edit context.
    def current_ids(model)
      current(model).map(&:persistent_id)
    end

    def entities(model)
      model.respond_to?(:active_entities) ? model.active_entities : model.entities
    end

    # Refuses a path change a view command asks of a Model SketchUp is not showing. SketchUp honors a deeper
    # path there but reports the change to the shown Model's observers, and ignores a return to the root
    # (context/SKETCHUP_HOST_BEHAVIOR.md), so navigation needs the shown Model either way.
    def shown!(model)
      return if model.equal?(Sketchup.active_model)

      raise CodedError.new("session.inactive", "SketchUp moves the open Group only in the Model it shows; switch " \
                                               "to this Model's window first. Nothing moved.")
    end

    # Opens `path` (Groups and ComponentInstances, outermost first) as the edit context. Each boundary
    # runs first; a path equal to the current one is not assigned again, so the host reports no change.
    # SketchUp ignores a return to the root on a Model that is not the active document
    # (context/SKETCHUP_HOST_BEHAVIOR.md), so that move is refused before any boundary writes.
    def enter(model, path)
      path = Array(path)
      if path.empty? && !current(model).empty? && !model.equal?(Sketchup.active_model)
        raise CodedError.new("session.inactive", "SketchUp closes Groups only in the Model it shows; switch to " \
                                                 "this Model's window first. Nothing moved.")
      end

      close(model, :to => path)
      model.active_path = path.empty? ? nil : path unless current(model) == path
      path
    end

    def enter_root(model)
      enter(model, [])
    end

    # Runs every boundary for leaving the current path for `to`, without changing the path: the hook a
    # save uses while the host forbids a path change. Answers the path the boundaries left open.
    def close(model, to:)
      from = current(model)
      boundaries.each_value { |boundary| boundary.call(model, from, Array(to)) }
      current(model)
    end

    # `block.call(model, from_path, to_path)` before any path change. Registered by name, so a reloaded
    # `install` replaces its boundary rather than adding a second.
    def boundary(name, &block)
      boundaries[name] = block
    end

    def boundaries
      @boundaries ||= {}
    end

    PhComposer.on_reset("edit_context") { @boundaries = {} } if PhComposer.respond_to?(:on_reset)
  end
end
