# frozen_string_literal: true

require_relative "../../../core/face_capture"
require_relative "../../../core/vector3"
require_relative "../placement/snap"
require_relative "read_context"
require_relative "native_unit"

module PhComposer
  module Windows
    module Units
      # Puts a Window that has left its Face back on the nearest Face of its Zone. The Face must be beside
      # it in its own parent storage, as a re-host's must. It writes only the instance's transform and glue,
      # and never a record, so it can join the native gesture that moved the Window (HostWatch).
      module ReturnToHost
        # A Window in one of these conditions is no longer sitting on a Face. An overlap is still on one.
        LEFT = %w[window.unhosted window.off_host window.overhang].freeze
        NOT_RIGID = { :scaled => ["window.scaled", "scaled"], :sheared => ["window.sheared", "sheared"],
                      :mirrored => ["window.mirrored", "mirrored"] }.freeze

        module_function

        # Answers whether the Window was out of place. One that still sits on its Face writes nothing.
        def call(request, proposal, unit:)
          item = Occurrences.resolve(request.model, unit)
          reads = ReadContext.new(request)
          type = reads.type(item)
          id = item.record.fetch("id")
          return { "unit_id" => id, "returned" => false } unless left?(item, type, reads.host(item, :writable => false))

          plan = returnable!(item, type)
          host, matrix = landing(request, item, plan, reads)
          proposal.add_step(ReturnStep.new(:item => item, :host => host, :matrix => matrix), :scopes => [])
          { "unit_id" => id, "returned" => true }
        end

        def left?(item, type, host)
          findings = State.findings(item, :type => type, :canonical_definition => nil,
                                          :host_geometry => host&.geometry, :host_values => host&.values || {})
          (findings.map { |finding| finding.fetch("code") } & LEFT).any?
        end

        # The Window's own state must allow a new placement, and its drawn outline must be its Type's.
        def returnable!(item, type)
          raise CodedError.new("window.unknown_type", "The Window's Type is not in the Model.") unless type

          Occurrences.mutable!(item)
          transform = WorldGeometry.transform_state(item.transform.to_a)
          NOT_RIGID.each do |state, (code, word)|
            raise CodedError.new(code, "A #{word} Window cannot return to a Face.") if transform[state]
          end
          plan = DefinitionPlan.build(type)
          definition = item.entity.definition
          return plan if DefinitionGeometry.matches?(definition, :type_id => type.fetch("id"), :plan => plan)

          raise CodedError.new("window.definition_changed", "Reset the Window geometry to its Type first.")
        end

        # The nearest Face that can take the Window, written as a located host, and its matrix there.
        def landing(request, item, plan, reads)
          matrix = item.transform.to_a
          centre = Placement::Snap.centre_m(plan, matrix)
          others = reads.other_polygons(:except => [item.path])
          hosts = reads.sibling_hosts(item).filter_map do |host|
            placed = Placement::Snap.on_face(host.geometry, plan, matrix, others)
            placed && [host, placed, Vector3.length(Vector3.subtract(Placement::Snap.centre_m(plan, placed), centre))]
          end
          host, placed, = hosts.min_by(&:last)
          unless host
            raise CodedError.new("window.no_host_face", "No Face of a Zone beside this Window has room for it.")
          end

          [Placement::Hosts.writable(request, host.reference), placed]
        end
        private_class_method :left?, :returnable!, :landing
      end

      # Moves one Window onto its Face and glues it there, all in the instance's own transform and glue.
      class ReturnStep
        attr_reader :affected

        def initialize(item:, host:, matrix:)
          @reference = DeepCopy.call(item.reference)
          @record = DeepCopy.call(item.record)
          @native_before = NativeUnit.preimage(item)
          @locator = host.locator or raise ArgumentError, "A return target must be located."
          @host_reference = DeepCopy.call(host.reference)
          @host_geometry = DeepCopy.call(host.geometry.to_h)
          @local = (host.transform.inverse * Geom::Transformation.new(matrix)).to_a
          @affected = [{ "kind" => REFERENCE_KIND, "id" => @record.fetch("id"), "change" => "rehosted",
                         "reference" => DeepCopy.call(@reference) }]
          @captured = nil
        end

        def descriptor
          DeepCopy.call("name" => "return_window_to_host", "reference" => @reference, "record" => @record,
                        "native_before" => @native_before, "host" => @host_reference,
                        "host_geometry" => @host_geometry, "matrix" => @local)
        end

        def temporary_ids
          []
        end

        def apply(model, _slots)
          item = Occurrences.resolve(model, @reference, :mutable => true)
          unless item.record == @record && NativeUnit.preimage(item) == @native_before
            NativeUnit.changed!("The Window moved before it could return to its Face.")
          end
          located = @locator.call(model, @host_reference, :mutable => true)
          unless FaceCapture.call(located.entity, located.transform).to_h == @host_geometry
            NativeUnit.changed!("The host Face changed before the Window could return to it.")
          end
          entity = item.entity
          @captured = [entity, entity.transformation.to_a, entity.glued_to]
          entity.transformation = Geom::Transformation.new(@local)
          entity.glued_to = located.entity
          return if entity.glued_to == located.entity

          raise CodedError.new("geometry.failed", "The Window could not glue to the Face it returned to.")
        end

        # Writes back what `apply` changed; nothing when apply did not reach its writes.
        def restore
          return unless @captured

          entity, matrix, glue = @captured
          entity.transformation = Geom::Transformation.new(matrix)
          entity.glued_to = glue
        end
      end
    end
  end
end
