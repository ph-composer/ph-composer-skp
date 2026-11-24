# frozen_string_literal: true

module PhComposer
  module Piping
    module Assignment
      # The pipe reference target: the records provider the engine's reference scan reads, so a Pipe Type a pipe
      # names cannot be deleted unseen, and the resolver every write goes through. A pipe's reference names its
      # Piping group's path and the Edge's own root-to-Edge path; the Edge must sit directly in that group.
      module Target
        PATH = Group::Target::PATH
        REFERENCE = {
          "type" => "object", "additionalProperties" => false, "required" => %w[group_path entity_path entity_id],
          "properties" => {
            "group_path" => PATH.merge("minItems" => 1, "description" => "The root-to-Group path of the Piping " \
                                                                         "group holding the Edge."),
            "entity_path" => PATH.merge("minItems" => 2, "description" => "The root-to-Edge path: group_path and " \
                                                                          "the Edge's persistent id."),
            "entity_id" => { "type" => %w[string null],
                             "description" => "The Edge's assignment id, or null for an Edge with none." }
          }
        }.freeze

        module_function

        # Every Edge carrying a pipe record whose text is a JSON object, anywhere in the Model and once per
        # placement, keyed by its root-to-Edge path, inside a Piping group or stranded outside one.
        def entries(model)
          found = []
          each_tagged(model) do |edge, path|
            record, = Group.read(edge, STORE)
            record &&= Group.scannable(record)
            found << Records::ReferenceEntry.new(:kind => PIPE_KIND, :key => path, :record => record) if record
          end
          found
        end

        def each_tagged(model)
          pending = [[model.entities, []]]
          until pending.empty?
            entities, path = pending.shift
            entities.each do |entity|
              current = path + [entity.persistent_id]
              if entity.is_a?(Sketchup::Edge)
                yield entity, current if STORE.marks?(entity)
              elsif (contents = Group.contents(entity))
                pending << [contents, current]
              end
            end
          end
        end

        # The strict resolver: every step of the path, an Edge whose parent is a Piping group and is the group the
        # reference names with a readable record, no Piping group above it, the Edge's record the one the reference
        # read and, when
        # `mutable`, no locked or shared step.
        def locate(model, reference, mutable:, index: nil)
          path = reference.fetch("entity_path")
          entities = Group::Target.along!(model, path, index)
          edge = entities.last
          raise CodedError.new("target.wrong_kind", "The path does not name an Edge.") unless
            edge.is_a?(Sketchup::Edge)

          containers = entities[0...-1]
          unless containers.last && Group.piping_group?(containers.last)
            raise CodedError.new(Codes::OUTSIDE_GROUP, "The Edge is not directly inside a Piping group.")
          end
          unless path[0...-1] == reference.fetch("group_path")
            raise CodedError.new("target.wrong_hierarchy", "The Edge is not in the Piping group the reference names.")
          end

          group_record, problem = Group.read(containers.last)
          raise CodedError.new("record.unreadable", "The Piping group's #{problem}") if problem

          Group.validate!(group_record)

          Group::Target.raise_refusal(Group::Target.nested_refusal(containers[0...-1]))
          Group::Target.raise_refusal(Group::Target.write_refusal(containers)) if mutable
          check_identity!(stored!(edge), reference["entity_id"])
          Group::Target.located(PIPE_KIND, reference, model, entities)
        end

        # The Edge's stored record, or nil. Text that is not a JSON object refuses: a write through it would destroy
        # what a later repair could still show.
        def stored!(edge)
          record, problem = Group.read(edge, STORE)
          raise CodedError.new("record.unreadable", "#{problem} Erase the Edge or redraw it.") if problem

          record
        end

        def check_identity!(record, expected_id)
          if expected_id
            raise CodedError.new("target.not_found", "Edge #{expected_id} has no pipe assignment.") unless record
            return if record["id"] == expected_id

            raise CodedError.new("target.changed", "The Edge's pipe assignment has changed.")
          elsif Assignment.identity(record)
            raise CodedError.new("target.changed", "The Edge now has a pipe assignment.")
          end
        end
      end

      TARGET = Records::ReferenceTarget.new(
        :id => PIPE_KIND, :label => "Pipe", :schema_version => 1, :values => RECORD_KIND.values_schema,
        :occurrence => Target::REFERENCE, :records => Target.method(:entries),
        :validate => ->(record) { RECORD_KIND.problems(record) }, :references => RECORD_KIND.references,
        :locate => Target.method(:locate), :locate_index => ->(_model) { Zones::ChildLookup.new }
      )
    end
  end
end
