# frozen_string_literal: true

require_relative "state"
require_relative "generated_geometry"
require_relative "../placement/host"

module PhComposer
  module Windows
    module Units
      # One Window inventory per action or read, with no private Zone dictionaries. The Zones reads are
      # made on first use and once: the glued hosts' `host_context` rows and the Zone states when a
      # Unit's own host is asked for, and the Face target's read-phase index when a host is located.
      # Placing on one explicit host makes none of them. Include unglued occurrences when measuring
      # same-plane conflicts.
      class ReadContext
        attr_reader :occurrences

        def initialize(request)
          @request = request
          @occurrences = Occurrences.all(request.model)
          @types = request.engine.ids(TYPE_KIND).to_h { |id| [id, request.engine.find(TYPE_KIND, id)] }
          @hosts = {}
        end

        def type(item)
          @types[item.record.fetch("window_type_id")]
        end

        def polygon(item)
          authored = type(item)
          definition = item.entity.definition
          type_id = item.record.fetch("window_type_id")
          plan = authored && DefinitionPlan.build(authored)
          primary_id = DefinitionIndex.read(@request.model)[type_id]
          if plan && primary_id == definition.persistent_id &&
             DefinitionGeometry.matches?(definition, :type_id => type_id, :plan => plan)
            # An all-Empty definition has no pane bounds. Its generation datum still carries
            # a stale native footprint even when the current empty Type has different dimensions.
            stamp = DEFINITION_STORE.read(definition)
            if stamp.key?("generated_size_m")
              generated = GeneratedGeometry.plan(definition, :type_id => type_id)
              plan = generated unless [plan.width_m, plan.height_m] == [generated.width_m, generated.height_m]
            end
          else
            plan = GeneratedGeometry.plan(definition, :type_id => type_id)
          end
          WorldGeometry.map(plan, item.transform.to_a).outer_polygon_m
        end

        # Uncertain native geometry remains readable, but cannot supply a mutation footprint.
        # Malformed persisted records continue to refuse rather than disappearing from reads.
        def read_polygon(item)
          polygon(item)
        rescue CodedError => error
          raise unless error.code == "window.type_geometry_unknown"

          nil
        end

        def other_polygons(except: [])
          occurrences.reject { |item| except.include?(item.path) }.map { |item| polygon(item) }
        end

        # The Zone Face a Unit is glued to, or nil. Writable hosts are located through Zones' resolver.
        def host(item, writable: true)
          path = glued_path(item)
          row = path && rows[path]
          return nil unless row

          @hosts[[path, writable]] ||= if writable
                                         Placement::Hosts.writable(@request, row.fetch("reference"),
                                                                   :row => row,
                                                                   :index => locate_index)
                                       else
                                         Placement::Hosts.read(item.entity.glued_to, item.path[0...-1],
                                                               item.parent_transform, row,
                                                               Placement::Hosts.zone_state(zone_states,
                                                                                           row))
                                       end
        end

        def host_reference(reference)
          Placement::Hosts.writable(@request, reference)
        end

        # The occurrence reference of the Zone Face a Unit is glued to, or nil.
        def glued_reference(item)
          path = glued_path(item)
          path && rows[path]&.fetch("reference")
        end

        private

        def rows
          @rows ||= Placement::Hosts.context(@request, @occurrences.filter_map { |item| glued_path(item) })
        end

        def zone_states
          @zone_states ||= Placement::Hosts.zone_states(@request.query(Placement::Hosts::ZONES).fetch("zones"))
        end

        # Shared by every host this read locates, so a batch over many hosts walks the Zones once.
        def locate_index
          @locate_index ||= @request.locate_index(Placement::Hosts::FACE_KIND)
        end

        def glued_path(item)
          face = item.entity.glued_to
          face && item.path[0...-1] + [face.persistent_id]
        end
      end
    end
  end
end
