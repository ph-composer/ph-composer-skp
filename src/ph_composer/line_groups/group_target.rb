# frozen_string_literal: true

module PhComposer
  module LineGroups
    # The group target's walk and resolver, and the path rules the Edge target shares. Outside every Zone, a group is
    # named by its root-to-Group path and record id, and `locate` walks that path itself.
    module GroupTarget
      module_function

      # Every line group occurrence whose record is a JSON object, keyed by its root-to-Group path, through Groups and
      # components, once per placement, so a pasted copy is its own entry.
      def entries(spec, model)
        found = []
        each_group(spec, model) do |group, path|
          record, = LineGroups.read(group, spec.group_store)
          record &&= LineGroups.scannable(record)
          found << Records::ReferenceEntry.new(:kind => spec.group_kind, :key => path, :record => record) if record
        end
        found
      end

      # Each Group carrying the line group record, readable or not, with its root-to-Group path and the entities
      # along it, root first.
      def each_group(spec, model)
        pending = [[model.entities, [], []]]
        until pending.empty?
          entities, path, along = pending.shift
          entities.each do |entity|
            contents = LineGroups.contents(entity)
            next unless contents

            current = path + [entity.persistent_id]
            yield entity, current, along + [entity] if spec.group?(entity)
            pending << [contents, current, along + [entity]]
          end
        end
      end

      # The entities a root-to-entity path names, root first, each the one child of the one before. `index`
      # (`matching(entities, persistent_id)`) lets a command resolving many paths read each collection once.
      def along!(model, path, index = nil)
        entities = model.entities
        path.each_with_index.map do |persistent_id, step|
          matches = if entities.nil? then []
                    elsif index then index.matching(entities, persistent_id)
                    else entities.to_a.select { |entity| entity.persistent_id == persistent_id }
                    end
          raise CodedError.new("target.not_found", "Entity #{persistent_id} no longer exists.") if matches.empty?
          if matches.length > 1
            raise CodedError.new("target.ambiguous", "Entity #{persistent_id} resolves more than once.")
          end

          entity = matches.first
          entities = LineGroups.contents(entity)
          if entities.nil? && step < path.length - 1
            raise CodedError.new("target.wrong_kind", "Entity #{persistent_id} is not a Group or component.")
          end

          entity
        end
      end

      # What a write through these containers meets, as `{ code, message }`, or nil: a component on the path (a line
      # group sits at the root or in plain Groups, and a write's scope is a Group path), a locked step, or storage
      # another placement draws (a pasted Group not yet made unique).
      def write_refusal(spec, containers)
        unless containers.all? { |entity| entity.is_a?(Sketchup::Group) }
          return { "code" => "target.wrong_hierarchy",
                   "message" => "A #{spec.label} sits at the Model root or in plain Groups, not in a component." }
        end
        if containers.any? { |entity| entity.respond_to?(:locked?) && entity.locked? }
          return { "code" => "target.locked", "message" => "A Group on the path is locked; unlock it first." }
        end
        return nil unless containers.any? { |entity| entity.definition.instances.length > 1 }

        { "code" => "target.shared_definition",
          "message" => "The #{spec.label} shares its storage with a copy; open it with Edit Group and close it, " \
                       "or make it unique, first." }
      end

      # Inside another line group of its kind; inside a Zone is the caller's containment read to say.
      def nested_refusal(spec, above)
        return nil unless above.any? { |entity| spec.group?(entity) }

        { "code" => spec.code(:group_nested),
          "message" => "The #{spec.label} sits inside another #{spec.label}; move it out first." }
      end

      def raise_refusal(refusal)
        raise CodedError.new(refusal.fetch("code"), refusal.fetch("message")) if refusal
      end

      # The strict resolver. Refuses a path that no longer resolves, a leaf that is no line group or whose record is
      # not the one named, a line group inside another and, when `mutable`, a locked or shared step.
      def locate(spec, model, reference, mutable:, index: nil)
        path = reference.fetch("group_path")
        entities = along!(model, path, index)
        group = entities.last
        raise CodedError.new("target.wrong_kind", "The path does not name a #{spec.label}.") unless spec.group?(group)

        record, problem = LineGroups.read(group, spec.group_store)
        raise CodedError.new("record.unreadable", problem) if problem
        raise CodedError.new("target.changed", "The #{spec.label}'s identity has changed.") unless
          record["id"] == reference.fetch("group_id")

        raise_refusal(nested_refusal(spec, entities[0...-1]))
        raise_refusal(write_refusal(spec, entities)) if mutable
        located(spec.group_kind, reference, model, entities)
      end

      # A LocatedEntity for the last of `entities`, with the collection holding it and its parent-to-world transform.
      def located(kind, reference, model, entities)
        above = entities[0...-1]
        Records::LocatedEntity.new(
          :kind => kind, :reference => DeepCopy.call(reference), :entity => entities.last,
          :entities => above.empty? ? model.entities : LineGroups.contents(above.last),
          :transform => above.reduce(Geom::Transformation.new) { |carried, entity| carried * entity.transformation },
          :parent_path => above.map(&:persistent_id)
        )
      end
    end
  end
end
