# frozen_string_literal: true

module PhComposer
  module LineGroups
    # The Edge target's records, which the engine's reference scan reads, and the resolver every write goes through.
    # A reference names the group's path and the Edge's root-to-Edge path; the Edge sits directly in that group.
    module EdgeTarget
      module_function

      # Every Edge carrying the assignment record whose text is a JSON object, anywhere in the Model and once per
      # placement, keyed by its root-to-Edge path, inside a line group or stranded outside one.
      def entries(spec, model)
        found = []
        each_tagged(spec, model) do |edge, path|
          record, = LineGroups.read(edge, spec.edge_store)
          record &&= LineGroups.scannable(record)
          found << Records::ReferenceEntry.new(:kind => spec.edge_kind, :key => path, :record => record) if record
        end
        found
      end

      def each_tagged(spec, model)
        pending = [[model.entities, []]]
        until pending.empty?
          entities, path = pending.shift
          entities.each do |entity|
            current = path + [entity.persistent_id]
            if entity.is_a?(Sketchup::Edge)
              yield entity, current if spec.edge_store.marks?(entity)
            elsif (contents = LineGroups.contents(entity))
              pending << [contents, current]
            end
          end
        end
      end

      # The strict resolver: every step, an Edge directly in the named group with a readable record, no line group
      # above it, the Edge's record the one the reference read and, when `mutable`, no locked or shared step.
      def locate(spec, model, reference, mutable:, index: nil)
        path = reference.fetch("entity_path")
        entities = GroupTarget.along!(model, path, index)
        edge = entities.last
        raise CodedError.new("target.wrong_kind", "The path does not name an Edge.") unless edge.is_a?(Sketchup::Edge)

        containers = entities[0...-1]
        unless containers.last && spec.group?(containers.last)
          raise CodedError.new(spec.code(:outside_group), "The Edge is not directly inside a #{spec.label}.")
        end
        unless path[0...-1] == reference.fetch("group_path")
          raise CodedError.new("target.wrong_hierarchy", "The Edge is not in the #{spec.label} the reference names.")
        end

        group_record, problem = LineGroups.read(containers.last, spec.group_store)
        raise CodedError.new("record.unreadable", "The #{spec.label}'s #{problem}") if problem

        spec.validate_group!(group_record)

        GroupTarget.raise_refusal(GroupTarget.nested_refusal(spec, containers[0...-1]))
        GroupTarget.raise_refusal(GroupTarget.write_refusal(spec, containers)) if mutable
        check_identity!(spec, stored!(spec, edge), reference["entity_id"])
        GroupTarget.located(spec.edge_kind, reference, model, entities)
      end

      # The Edge's stored record, or nil. Text that is not a JSON object refuses: a write through it would destroy what
      # a later repair could still show.
      def stored!(spec, edge)
        record, problem = LineGroups.read(edge, spec.edge_store)
        raise CodedError.new("record.unreadable", "#{problem} Erase the Edge or redraw it.") if problem

        record
      end

      def check_identity!(spec, record, expected_id)
        noun = spec.edge_noun
        if expected_id
          raise CodedError.new("target.not_found", "Edge #{expected_id} has no #{noun} assignment.") unless record
          return if record["id"] == expected_id

          raise CodedError.new("target.changed", "The Edge's #{noun} assignment has changed.")
        elsif spec.edge_identity(record)
          raise CodedError.new("target.changed", "The Edge now has a #{noun} assignment.")
        end
      end
    end
  end
end
