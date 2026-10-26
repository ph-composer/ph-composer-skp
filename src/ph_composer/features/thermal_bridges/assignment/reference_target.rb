# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    module Assignment
      # The Edge reference target: the records provider the engine's incoming-reference scan reads, so a
      # Thermal Bridge Type an Edge names cannot be deleted, and the resolver every write goes through.
      module Target
        PATH = { "type" => "array", "items" => { "type" => "integer" } }.freeze
        # The Face reference shape (context/CONTRACTS.md, "Geometry records and occurrence references"):
        # an Edge is assignable only inside a Zone, so its reference starts from the Zone that holds it.
        REFERENCE = {
          "type" => "object", "additionalProperties" => false,
          "required" => %w[zone_id zone_path entity_path entity_id],
          "properties" => {
            "zone_id" => { "type" => "string" }, "zone_path" => PATH,
            "entity_path" => PATH.merge("minItems" => 1),
            "entity_id" => { "type" => %w[string null],
                             "description" => "The Edge's assignment id, or null for an Edge with none." }
          }
        }.freeze

        module_function

        # Every tagged Edge in the Model, inside every Group and ComponentInstance, shared definitions and
        # cutting components included: an orphaned or shared tag still names its type. Keys are the
        # root-to-Edge persistent-id paths, so each placement of a shared definition is its own entry.
        def entries(model)
          found = []
          pending = [[model.entities, []]]
          until pending.empty?
            entities, path = pending.shift
            entities.each do |entity|
              current = path + [entity.persistent_id]
              if entity.is_a?(Sketchup::Edge)
                record = STORE.read(entity)
                found << Records::ReferenceEntry.new(:kind => EDGE_KIND, :key => current, :record => record) if record
              elsif entity.is_a?(Sketchup::Group)
                pending << [entity.entities, current]
              elsif entity.is_a?(Sketchup::ComponentInstance)
                pending << [entity.definition.entities, current]
              end
            end
          end
          found
        end

        # The strict resolver. Zones resolves the Zone and every step inside it, and refuses what a write
        # through the path meets (Zones::Occurrences.resolve_element); this checks the leaf is an Edge and
        # that its record is the one the reference read. A duplicated `tbe_` id is not refused: copies are
        # routine and the path, not the id, names the occurrence. Its `index:` is the one `index` builds.
        def locate(model, reference, mutable:, index: nil)
          occurrence = Zones::Occurrences.resolve_element(model, reference, :noun => "Edge", :mutable => mutable,
                                                                            :index => index)
          edge = occurrence.entity
          unless edge.is_a?(Sketchup::Edge)
            raise CodedError.new("target.wrong_kind", "The occurrence does not resolve to an Edge.")
          end

          # The record as stored, not validated, so an invalid assignment can still be cleared or replaced.
          check_identity!(STORE.read(edge), reference["entity_id"])
          Records::LocatedEntity.new(:kind => EDGE_KIND, :reference => DeepCopy.call(reference), :entity => edge,
                                     :entities => occurrence.entities, :transform => occurrence.transform,
                                     :parent_path => occurrence.zone.path + occurrence.path[0...-1])
        end

        # A read-phase index: Zones' walk of the Model, which resolving each target's Zone reuses.
        def index(model)
          Zones::Index.new(model)
        end

        # A null `entity_id` names an Edge with no assignment, or one whose record holds no valid id, which a
        # write then guards by its values.
        def check_identity!(record, expected_id)
          if expected_id
            raise CodedError.new("target.not_found", "Edge #{expected_id} has no assignment.") unless record
            return if record["id"] == expected_id

            raise CodedError.new("target.changed", "The Edge's assignment has changed.")
          elsif Assignment.identity(record)
            raise CodedError.new("target.changed", "The Edge now has an assignment.")
          end
        end
        private_class_method :check_identity!
      end

      TARGET = Records::ReferenceTarget.new(
        :id => EDGE_KIND, :label => "Thermal bridge Edge", :schema_version => 1, :values => RECORD_KIND.values_schema,
        :occurrence => Target::REFERENCE, :records => Target.method(:entries),
        :validate => ->(record) { RECORD_KIND.problems(record) }, :references => RECORD_KIND.references,
        :locate => Target.method(:locate), :locate_index => Target.method(:index)
      )
    end
  end
end
