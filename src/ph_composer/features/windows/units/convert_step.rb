# frozen_string_literal: true

require_relative "definition_index"
require_relative "definition_plan"
require_relative "definition_writer"
require_relative "mutation_scope"
require_relative "native_unit"
require_relative "world_geometry"
require_relative "convert_sources"
require_relative "convert_rectangles"
require_relative "../placement/fit"
require_relative "../placement/plane"
require_relative "../../../core/operations/entity_scope"

module PhComposer
  module Windows
    module Units
      # Convert to Window Type's one step: erases the drawn rectangles, which heals each host Face, then
      # places one Unit per group on it (W7-9). Detached values survive preview. A new Type is the caller's
      # to write and is not stored yet when this runs, as FlipStep's is not, so it is taken as a value here.
      #
      # While a drawn rectangle exists, its Face carries a copy of its host's Face record and the Zones
      # locator refuses that record as `target.ambiguous` (context/SKETCHUP_HOST_BEHAVIOR.md). The host
      # is located only after every rectangle is gone; the plan is read beforehand from the geometry the
      # host will have then.
      class ConvertStep
        attr_reader :affected, :definition_ids, :scopes

        # One Unit to place: its record, the Type it uses and the host it lands on.
        UnitPlan = Struct.new(:record, :type, :plan, :host_key, :matrix, :keyword_init => true)

        # `groups` are ConvertReview's built groups, each with the `:type` and `:record` it becomes.
        # `new_type_ids` are the Types the caller is writing in this proposal.
        def initialize(model:, groups:, new_type_ids:, locator:, existing_polygons_m:)
          @locator = locator
          @new_type_ids = new_type_ids.dup.freeze
          @index = DeepCopy.call(DefinitionIndex.read(model))
          @index.each_key { |id| DefinitionIndex.resolve(model, id) }
          @hosts = hosts_of(groups)
          @rectangles = groups.flat_map { |group| group.fetch(:sources).map { |source| rectangle(source) } }
          @placements = groups.map { |group| placement(group, existing_polygons_m) }
          @types = @placements.map(&:type).uniq { |type| type.fetch("id") }
          @definitions_before = existing_definitions(model)
          @definition_ids = @definitions_before.values.map { |row| row.fetch("id") }.freeze
          @affected = @placements.map do |item|
            { "kind" => REFERENCE_KIND, "id" => item.record.fetch("id"), "change" => "placed" }
          end
          @scopes = scopes_for.freeze
        end

        def descriptor
          DeepCopy.call("name" => "convert_to_window_type", "new_type_ids" => @new_type_ids, "types" => @types,
                        "index_before" => @index, "definitions_before" => @definitions_before,
                        "hosts" => @hosts.values.map { |host| host_descriptor(host) },
                        "rectangles" => @rectangles,
                        "placements" => @placements.map { |item| placement_descriptor(item) })
        end

        def temporary_ids
          new_types = @types.select { |type| @new_type_ids.include?(type.fetch("id")) }
          new_types.flat_map { |type| [type.fetch("id")] + type.fetch("elements").map { |cell| cell.fetch("id") } } +
            @placements.map { |item| item.record.fetch("id") }
        end

        def apply(model, slots)
          verify_definitions!(model)
          verify_and_erase_rectangles!(model)
          located = @hosts.to_h { |key, host| [key, healed_host(model, host)] }
          index = @index.dup
          @affected = @placements.map do |item|
            target = located.fetch(item.host_key)
            definition = definition_for(model, item, index)
            local = target.transform.inverse * Geom::Transformation.new(item.matrix)
            WorldGeometry.transform_state(local.to_a)
            instance = NativeUnit.add_glued!(target.entities, definition, local, target.entity, item.record)
            reference = { "unit_id" => item.record.fetch("id"),
                          "entity_path" => @hosts.fetch(item.host_key).fetch(:parent_path) + [instance.persistent_id] }
            slots[item.record.fetch("id")] = reference
            { "kind" => REFERENCE_KIND, "id" => item.record.fetch("id"), "change" => "placed",
              "reference" => reference }
          end
        end

        private

        # What each host will be once its rectangles are gone: every hole the rectangles fill is dropped.
        def hosts_of(groups)
          groups.group_by { |group| host_key(group.fetch(:host)) }.transform_values do |members|
            host = members.first.fetch(:host)
            outlines = members.map { |group| group_outline(group) }
            kept = host.geometry.holes.reject { |hole| outlines.any? { |outline| same_outline?(hole, outline) } }
            healed = FaceGeometry.build(:loops_m => [host.geometry.outer_loop] + kept, :normal => host.geometry.normal,
                                        :has_glued_instances => host.geometry.has_glued_instances)
            { :host => host, :healed => healed, :parent_path => host.parent_path.dup,
              :face_id => host.entity.persistent_id, :before_digest => host.geometry.digest,
              :transform => host.transform.to_a }
          end
        end

        def host_key(host)
          host.parent_path + [host.entity.persistent_id]
        end

        def group_outline(group)
          plane = plane_of(group)
          extents = group.fetch(:sources).map { |source| ConvertRectangles.extent(source.corners, plane) }
          left, right = extents.map(&:left).min, extents.map(&:right).max
          bottom, top = extents.map(&:bottom).min, extents.map(&:top).max
          [[left, bottom], [right, bottom], [right, top], [left, top]].map { |x, y| plane.world(x, y) }
        end

        def plane_of(group)
          Placement::Plane.new(group.fetch(:host).geometry)
        end

        # A hole is the rectangles' outline when its corners are, whichever vertex it starts from.
        def same_outline?(hole, outline)
          corners = ConvertRectangles.corners(hole)
          return false unless corners

          corners.all? do |corner|
            outline.any? do |point|
              corner.zip(point).all? { |a, b| (a - b).abs <= ConvertRectangles::COORDINATE_TOLERANCE_M }
            end
          end
        end

        def rectangle(source)
          { "path" => source.path.dup, "digest" => source.geometry.digest }
        end

        def placement(group, existing)
          host = @hosts.fetch(host_key(group.fetch(:host)))
          type = DeepCopy.call(group.fetch(:type))
          unless Types::KIND.problems(type).empty?
            raise CodedError.new("validation.failed", "Supply a valid Window Type for the converted rectangles.")
          end

          plan = DefinitionPlan.build(type)
          plane = plane_of(group)
          point = sill_center(group, plane)
          mapped = plane.map(plan, :point_m => point, :anchor => group.fetch(:record).fetch("anchor"))
          Placement::Fit.check!(host.fetch(:healed), mapped.outer_polygon_m, :existing_polygons_m => existing)
          matrix = plane.instance_matrix(mapped).freeze
          WorldGeometry.transform_state(matrix)
          UnitPlan.new(:record => DeepCopy.call(Units.validate!(group.fetch(:record))), :type => type, :plan => plan,
                       :host_key => host_key(group.fetch(:host)), :matrix => matrix)
        end

        def sill_center(group, plane)
          extents = group.fetch(:sources).map { |source| ConvertRectangles.extent(source.corners, plane) }
          plane.world((extents.map(&:left).min + extents.map(&:right).max) / 2.0, extents.map(&:bottom).min)
        end

        # The existing Types' primary definitions, by Type id, as a preview's pre-image.
        def existing_definitions(model)
          @types.reject { |type| @new_type_ids.include?(type.fetch("id")) }.each_with_object({}) do |type, found|
            definition = DefinitionIndex.resolve(model, type.fetch("id"))
            next unless definition

            NativeUnit.check_primary!(definition, :type_id => type.fetch("id"), :plan => DefinitionPlan.build(type))
            found[type.fetch("id")] = { "id" => definition.persistent_id,
                                        "before" => DefinitionGeometry.capture(definition) }
          end
        end

        def scopes_for
          parents = (@hosts.values.map { |host| host.fetch(:parent_path) } +
                     @rectangles.map { |rectangle| rectangle.fetch("path")[0...-1] }).uniq
          [MutationScope.new(:definition_ids => definition_ids)] +
            parents.map { |path| PhComposer::Operations::EntityScope.new(path) }
        end

        def host_descriptor(host)
          { "reference" => host.fetch(:host).reference, "parent_path" => host.fetch(:parent_path),
            "face_id" => host.fetch(:face_id), "before_digest" => host.fetch(:before_digest),
            "healed" => host.fetch(:healed).to_h, "transform" => host.fetch(:transform) }
        end

        def placement_descriptor(item)
          { "record" => item.record, "type_id" => item.type.fetch("id"), "host" => item.host_key,
            "matrix" => item.matrix }
        end

        def verify_definitions!(model)
          @new_type_ids.each do |id|
            next unless Types::KIND.store.ids(model).include?(id) || DefinitionIndex.read(model).key?(id)

            NativeUnit.changed!("The new Window Type's identity is already in use.")
          end
          @types.reject { |type| @new_type_ids.include?(type.fetch("id")) }.each do |type|
            unless Types::KIND.store.read(model, type.fetch("id")) == type
              NativeUnit.changed!("The authored Window Type changed after preview.")
            end
          end
          NativeUnit.changed!("The Window definition index changed after preview.") unless
            DefinitionIndex.read(model) == @index
          @definitions_before.each do |type_id, row|
            definition = DefinitionIndex.resolve(model, type_id)
            unless definition && DefinitionGeometry.capture(definition) == row.fetch("before")
              NativeUnit.changed!("The canonical Window definition changed after preview.")
            end
          end
        end

        # Each rectangle again from the Model, then erased with every Edge only rectangles and hosts use.
        def verify_and_erase_rectangles!(model)
          sources, unread = ConvertSources.read(model, @rectangles.map { |rectangle| rectangle.fetch("path") })
          NativeUnit.changed!("A drawn rectangle changed after preview.") unless unread.empty?
          expected = @rectangles.to_h { |rectangle| rectangle.values_at("path", "digest") }
          unless sources.all? { |source| source.geometry.digest == expected.fetch(source.path) }
            NativeUnit.changed!("A drawn rectangle changed after preview.")
          end
          hosts = live_hosts(model)
          faces = sources.map(&:face)
          sources.group_by(&:parent_path).each_value do |group|
            owners = faces + hosts
            edges = group.flat_map { |source| source.face.edges }.uniq.select { |edge| (edge.faces - owners).empty? }
            group.first.face.parent.entities.erase_entities(group.map(&:face) + edges)
          end
        end

        def live_hosts(model)
          @hosts.values.map do |host|
            entities = PhComposer::Operations::EntityScope.new(host.fetch(:parent_path)).resolve(model)
            face = entities.to_a.find { |entity| entity.persistent_id == host.fetch(:face_id) }
            unless face.is_a?(Sketchup::Face) &&
                   FaceCapture.call(face, Geom::Transformation.new(host.fetch(:transform))).digest ==
                   host.fetch(:before_digest)
              NativeUnit.changed!("The host Face changed after preview.")
            end
            face
          end
        end

        # The host found through Zones now that no copied record remains, and proved to be the healed Face.
        def healed_host(model, host)
          located = @locator.call(model, host.fetch(:host).reference, :mutable => true)
          unless FaceCapture.call(located.entity, located.transform).digest == host.fetch(:healed).digest
            raise CodedError.new("geometry.failed", "The host Face did not heal when its rectangles were erased.")
          end

          located
        end

        def definition_for(model, item, index)
          id = item.type.fetch("id")
          definition = DefinitionIndex.resolve(model, id) if index.key?(id)
          return definition if definition

          created = DefinitionWriter.create(:model => model, :type => item.type, :plan => item.plan)
          fresh = index.merge(id => created.persistent_id)
          DefinitionIndex.write(model, fresh, :expected => index)
          index.replace(fresh)
          created
        end
      end
    end
  end
end
