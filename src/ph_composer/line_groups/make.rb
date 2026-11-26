# frozen_string_literal: true

module PhComposer
  module LineGroups
    # Make <group>: loose lines already drawn in one collection, wrapped where they are in a new line group linked to
    # one record. SketchUp deletes a Group left empty at the commit that made it, so no line group starts empty
    # (context/SKETCHUP_HOST_BEHAVIOR.md, "Making a line group"). One rule answers the action and the selection read,
    # which reports it so the panel offers Make only when it can run.
    module Make
      module_function

      # The Edges `paths` (root-to-Edge, as the selection read gives them) name and the containers above them, root
      # first, all in one collection. Refuses a path that resolves to no Edge or to lines in two collections.
      def resolve!(spec, model, paths)
        index = spec.child_lookup.call
        found = paths.map { |path| GroupTarget.along!(model, path, index) }
        found.each_with_index do |along, at|
          next if along.last.is_a?(Sketchup::Edge)

          raise CodedError.new("target.wrong_kind", "#{paths[at].inspect} names no line; a #{spec.label} is made " \
                                                    "from Edges only.")
        end
        parents = found.map { |along| along[0...-1] }.uniq { |above| above.map(&:persistent_id) }
        if parents.length > 1
          raise CodedError.new("target.wrong_hierarchy", "The lines sit in #{parents.length} different Groups; " \
                                                         "make a #{spec.label} from lines drawn in one.")
        end

        [parents.first || [], found.map(&:last)]
      end

      # What making a group from `edges`, directly in the last of `containers`, meets, as `{ code, message }`, or nil
      # when it can run. `others` counts selected entities that are not Edges; `contained` answers containment rows
      # for root-to-entity paths (GroupOperations.contained).
      def refusal(spec, model, containers, edges, contained:, others: 0)
        shape_refusal(spec, model, containers, edges, others) ||
          placement_refusal(spec, containers, edges, contained)
      end

      # Lines, loose, in the open context: the group is made where they are drawn, the way native Make Group works.
      def shape_refusal(spec, model, containers, edges, others)
        if others.positive?
          return coded("target.wrong_kind", "Select lines only: #{others} other selected " \
                                            "#{others == 1 ? 'entity is' : 'entities are'} not a line.")
        end
        return coded("params.invalid", "Select the loose lines to make a #{spec.label} from.") if edges.empty?
        unless Array(model.active_path).map(&:persistent_id) == containers.map(&:persistent_id)
          return coded("target.edit_path_changed", "The lines are not in the open context; open the Group they are " \
                                                   "drawn in first.")
        end
        return nil if edges.all? { |edge| edge.faces.empty? }

        coded("target.wrong_kind", "A selected line bounds a Face; a #{spec.label} holds loose lines only.")
      end

      # The rule a line group's own writes follow: outside every line group of its kind, every Group another feature
      # owns and every Zone, reached through plain, unlocked, unshared Groups. A Zone holds the lines when it is above
      # them, so the containment read takes an Edge's own path.
      def placement_refusal(spec, containers, edges, contained)
        if containers.any? { |entity| spec.group?(entity) }
          return coded(spec.code(:group_nested), "The lines are already in a #{spec.label}.")
        end
        if Records::EntityStore.claimed?(containers)
          return coded("target.wrong_hierarchy", "The lines sit in a Group another PH-Composer feature owns; move " \
                                                 "them out first.")
        end
        zone = contained.call([(containers + [edges.first]).map(&:persistent_id)]).first["zone"]
        if zone
          return coded(spec.code(:group_in_zone), "The lines sit inside Zone #{zone.fetch('name')}; a #{spec.label} " \
                                                  "sits outside every Zone, so move them out first.")
        end

        GroupTarget.write_refusal(spec, containers)
      end

      def coded(code, message)
        { "code" => code, "message" => message }
      end
      private_class_method :shape_refusal, :placement_refusal, :coded
    end
  end
end
