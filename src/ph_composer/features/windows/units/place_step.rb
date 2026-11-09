# frozen_string_literal: true

require_relative "definition_writer"
require_relative "definition_index"
require_relative "definition_geometry"
require_relative "occurrences"
require_relative "native_unit"
require_relative "world_geometry"
require_relative "../placement/host"
require_relative "../placement/fit"
require_relative "../placement/offsets"

module PhComposer
  module Windows
    module Units
      # One caller-owned proposal step. Paths and authored values survive preview; live entities are resolved at apply.
      class PlaceStep
        attr_reader :affected, :definition_ids

        # `point_m` is where the record's anchor lands on the host. A caller that already knows the whole
        # world placement, as Restore does from the panes it adopts, passes `world_matrix` as well.
        def initialize(model:, host:, type:, record:, point_m:, existing_polygons_m: [],
                       expected_scope: nil, expected_state: nil, world_matrix: nil)
          @type = DeepCopy.call(type)
          @record = DeepCopy.call(Units.validate!(record))
          unless @record.fetch("window_type_id") == @type.fetch("id") && Types::KIND.problems(@type).empty?
            raise CodedError.new("validation.failed", "Choose the authored Window Type referenced by this unit.")
          end

          @plan = DefinitionPlan.build(@type)
          @locator = host.locator or raise ArgumentError, "A placement host must be located."
          @parent_path = host.parent_path.dup
          @face_id = host.entity.persistent_id
          @host_reference = DeepCopy.call(host.reference)
          @host_values = DeepCopy.call(host.values)
          @host_geometry = DeepCopy.call(host.geometry.to_h)
          @host_transform = host.transform.to_a
          @point_m = DeepCopy.call(point_m)
          @existing_polygons = DeepCopy.call(existing_polygons_m)
          @expected_scope, @expected_state = expected_scope, DeepCopy.call(expected_state)
          if expected_scope.nil? != expected_state.nil?
            raise ArgumentError, "A placement scope and its expected state must be supplied together."
          end

          @expected_index = DeepCopy.call(DefinitionIndex.read(model))
          @expected_index.each_key { |id| DefinitionIndex.resolve(model, id) }
          definition = DefinitionIndex.resolve(model, @type.fetch("id"))
          check_definition!(definition)
          @definition_before = definition && DefinitionGeometry.capture(definition)
          @definition_ids = definition ? [definition.persistent_id].freeze : [].freeze
          @world_matrix = world_matrix ? fitted(world_matrix, host.geometry) : placement_matrix(host.geometry)
          verify_type_and_identity!(model)
          @affected = [{ "kind" => REFERENCE_KIND, "id" => @record.fetch("id"), "change" => "placed" }]
        end

        def descriptor
          DeepCopy.call("name" => "place_window_unit", "record" => @record, "type" => @type,
                        "host" => @host_reference, "host_values" => @host_values, "parent_path" => @parent_path,
                        "face_id" => @face_id, "host_geometry" => @host_geometry, "host_transform" => @host_transform,
                        "point_m" => @point_m, "existing_polygons_m" => @existing_polygons,
                        "index_before" => @expected_index, "definition_before" => @definition_before,
                        "scope_path" => @expected_scope&.path, "scope_before" => @expected_state)
        end

        def temporary_ids
          [@record.fetch("id")]
        end

        def apply(model, slots)
          verify_type_and_identity!(model)
          if @expected_scope && !@expected_scope.unchanged?(model, @expected_state)
            NativeUnit.changed!("The placement scope changed after preview.")
          end
          located = @locator.call(model, @host_reference, :mutable => true)
          entities, face, transform = located.entities, located.entity, located.transform
          geometry = FaceCapture.call(face, transform)
          unless geometry.to_h == @host_geometry && transform.to_a == @host_transform
            NativeUnit.changed!("The host Face changed after preview.")
          end
          unless DefinitionIndex.read(model) == @expected_index
            NativeUnit.changed!("The Window definition index changed after preview.")
          end
          @expected_index.each_key { |id| DefinitionIndex.resolve(model, id) }
          definition = DefinitionIndex.resolve(model, @type.fetch("id"))
          current = definition && DefinitionGeometry.capture(definition)
          unless current == @definition_before
            NativeUnit.changed!("The canonical Window definition changed after preview.")
          end
          check_definition!(definition)
          Placement::Fit.check!(geometry, WorldGeometry.map(@plan, @world_matrix).outer_polygon_m,
                                :existing_polygons_m => @existing_polygons)
          WorldGeometry.transform_state(transform.to_a)
          local_transform = transform.inverse * Geom::Transformation.new(@world_matrix)
          WorldGeometry.transform_state(local_transform.to_a)
          definition ||= create_definition(model)
          instance = NativeUnit.add_glued!(entities, definition, local_transform, face, @record)
          reference = { "unit_id" => @record.fetch("id"), "entity_path" => @parent_path + [instance.persistent_id] }
          slots[@record.fetch("id")] = reference
          @affected = [{ "kind" => REFERENCE_KIND, "id" => @record.fetch("id"), "change" => "placed",
                         "reference" => reference }]
        end

        private

        def placement_matrix(geometry)
          plane = Placement::Plane.new(geometry)
          mapped = plane.map(@plan, :point_m => @point_m, :anchor => @record.fetch("anchor"))
          Placement::Fit.check!(geometry, mapped.outer_polygon_m, :existing_polygons_m => @existing_polygons)
          matrix = plane.instance_matrix(mapped)
          WorldGeometry.transform_state(matrix)
          matrix.freeze
        end

        def fitted(world_matrix, geometry)
          WorldGeometry.transform_state(world_matrix)
          Placement::Fit.check!(geometry, WorldGeometry.map(@plan, world_matrix).outer_polygon_m,
                                :existing_polygons_m => @existing_polygons)
          world_matrix
        end

        def verify_type_and_identity!(model)
          unless Types::KIND.store.read(model, @type.fetch("id")) == @type
            NativeUnit.changed!("The authored Window Type changed after preview.")
          end
          if Occurrences.all(model).any? { |item| item.record.fetch("id") == @record.fetch("id") }
            NativeUnit.changed!("The new Window unit identity is already in use.")
          end
        end

        def check_definition!(definition)
          NativeUnit.check_primary!(definition, :type_id => @type.fetch("id"), :plan => @plan) if definition
        end

        def create_definition(model)
          definition = DefinitionWriter.create(:model => model, :type => @type, :plan => @plan)
          DefinitionIndex.write(model, @expected_index.merge(@type.fetch("id") => definition.persistent_id),
                                :expected => @expected_index)
          definition
        end
      end
    end
  end
end
