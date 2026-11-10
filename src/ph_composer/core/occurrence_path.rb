# frozen_string_literal: true

module PhComposer
  # The read-only walk of a root-to-container path, through Groups and components alike, for reads that
  # list what is inside one container without the user selecting it (context/AGENT_INTERFACE.md, "Model
  # context"). It reports what a write resolver refuses (a lock, a hidden step, storage another placement
  # shares) instead of refusing it, so a read can say why an action would. It names no feature.
  module OccurrencePath
    # One resolved container: `instances` are the Groups and components along the path, outermost first;
    # `entities` the collection the last one holds, or the Model's at the root; `transform` maps that
    # collection's contents to world coordinates, composed once from the root, which gives world positions
    # whether or not a context is open (context/SKETCHUP_HOST_BEHAVIOR.md, "Observers and edit contexts").
    # `locked`, `hidden` and `shared` are true when any step along the path is.
    Resolved = Struct.new(:path, :instances, :entities, :transform, :locked, :hidden, :shared, keyword_init: true)

    module_function

    def resolve(model, path)
      ids = integer_path(path)
      entities = model.entities
      instances = ids.map do |id|
        matches = entities.to_a.select { |entity| entity.persistent_id == id }
        raise CodedError.new("target.not_found", "No single entity #{id} is at that step.") unless matches.length == 1

        entity = matches.first
        entities = contents(entity)
        unless entities
          raise CodedError.new("target.wrong_kind", "Entity #{id} is not a Group or component, so it holds nothing.")
        end

        entity
      end
      transform = instances.reduce(Geom::Transformation.new) { |carried, entity| carried * entity.transformation }
      Resolved.new(:path => ids, :instances => instances, :entities => entities, :transform => transform,
                   :locked => instances.any?(&:locked?), :hidden => instances.any? { |entity| hidden?(entity) },
                   :shared => instances.any? { |entity| shared?(entity) })
    end

    def integer_path(value)
      raise ArgumentError unless value.is_a?(Array)

      value.map { |id| Integer(id) }
    rescue ArgumentError, TypeError
      raise CodedError.new("params.invalid", "A path holds persistent-id integers only.")
    end

    # A Group's or component's contents; nil for anything that holds nothing.
    def contents(entity)
      if entity.is_a?(Sketchup::Group)
        entity.entities
      elsif entity.is_a?(Sketchup::ComponentInstance)
        entity.definition.entities
      end
    end

    # Hidden itself, or on a tag that is hidden, or in a hidden tag folder.
    def hidden?(entity)
      return true if entity.respond_to?(:hidden?) && entity.hidden?

      tag = entity.respond_to?(:layer) ? entity.layer : nil
      while tag
        return true if tag.respond_to?(:visible?) && !tag.visible?

        tag = tag.respond_to?(:folder) ? tag.folder : nil
      end
      false
    end

    # Component storage, or a Group whose definition another Group shares: what is inside it is drawn by every
    # placement, so a write to one occurrence would reach the others.
    def shared?(entity)
      return true if entity.is_a?(Sketchup::ComponentInstance)

      definition = entity.respond_to?(:definition) ? entity.definition : nil
      definition.respond_to?(:instances) && definition.instances.length > 1
    end
  end
end
