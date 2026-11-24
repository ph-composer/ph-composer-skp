# frozen_string_literal: true

module PhComposer
  module Piping
    module Group
      # The Piping group reference target, and the path rules the pipe target shares. A Piping group sits outside
      # every Zone, so Zones' resolver does not apply: a reference names the Group by its root-to-Group persistent-id
      # path and its `ppg_` id, and `locate` walks that path itself, step by step.
      module Target
        PATH = { "type" => "array", "items" => { "type" => "integer" } }.freeze
        REFERENCE = {
          "type" => "object", "additionalProperties" => false, "required" => %w[group_id group_path],
          "properties" => {
            "group_id" => { "type" => "string", "description" => "The Piping group's ppg_ id." },
            "group_path" => PATH.merge("minItems" => 1,
                                       "description" => "The root-to-Group persistent-id path, one per placement.")
          }
        }.freeze

        module_function

        # Every Piping group occurrence whose record is a JSON object, keyed by its root-to-Group path, through
        # Groups and components, once per placement, so a pasted copy is its own entry.
        def entries(model)
          found = []
          each_group(model) do |group, path|
            record, = Group.read(group)
            found << Records::ReferenceEntry.new(:kind => GROUP_KIND, :key => path, :record => record) if record
          end
          found
        end

        # Each Group carrying a Piping group record, readable or not, with its root-to-Group path and the entities
        # along it, root first.
        def each_group(model)
          pending = [[model.entities, [], []]]
          until pending.empty?
            entities, path, along = pending.shift
            entities.each do |entity|
              contents = Group.contents(entity)
              next unless contents

              current = path + [entity.persistent_id]
              yield entity, current, along + [entity] if Group.piping_group?(entity)
              pending << [contents, current, along + [entity]]
            end
          end
        end

        # The entities a root-to-entity path names, root first, each the one child of the one before. `index`, a
        # Zones::ChildLookup, lets a command resolving many paths read each collection once.
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
            entities = Group.contents(entity)
            if entities.nil? && step < path.length - 1
              raise CodedError.new("target.wrong_kind", "Entity #{persistent_id} is not a Group or component.")
            end

            entity
          end
        end

        # What a write through these containers meets, as `{ code, message }`, or nil: a locked step, or storage
        # another placement draws (a pasted Group not yet made unique, a component placed twice).
        def write_refusal(containers)
          if containers.any? { |entity| entity.respond_to?(:locked?) && entity.locked? }
            return { "code" => "target.locked", "message" => "A Group on the path is locked; unlock it first." }
          end
          return nil unless containers.any? { |entity| entity.definition.instances.length > 1 }

          { "code" => "target.shared_definition",
            "message" => "The Piping group shares its storage with a copy; open it with Edit Group and close it, " \
                         "or make it unique, first." }
        end

        # Where a Piping group may not sit, read from the containers above it: inside another Piping group.
        # Inside a Zone is Zones' to say (ph_composer.zones.containment).
        def nested_refusal(above)
          return nil unless above.any? { |entity| Group.piping_group?(entity) }

          { "code" => Codes::GROUP_NESTED,
            "message" => "The Piping group sits inside another Piping group; move it out first." }
        end

        def raise_refusal(refusal)
          raise CodedError.new(refusal.fetch("code"), refusal.fetch("message")) if refusal
        end

        # The strict resolver. Refuses a path that no longer resolves, a leaf that is no Piping group or whose
        # record is not the one named, a Piping group inside another and, when `mutable`, a locked or shared step.
        def locate(model, reference, mutable:, index: nil)
          path = reference.fetch("group_path")
          entities = along!(model, path, index)
          group = entities.last
          raise CodedError.new("target.wrong_kind", "The path does not name a Piping group.") unless
            Group.piping_group?(group)

          record, problem = Group.read(group)
          raise CodedError.new("record.unreadable", problem) if problem
          raise CodedError.new("target.changed", "The Piping group's identity has changed.") unless
            record["id"] == reference.fetch("group_id")

          raise_refusal(nested_refusal(entities[0...-1]))
          raise_refusal(write_refusal(entities)) if mutable
          located(GROUP_KIND, reference, model, entities)
        end

        # A LocatedEntity for the last of `entities`, with the collection holding it and its parent-to-world
        # transform.
        def located(kind, reference, model, entities)
          above = entities[0...-1]
          Records::LocatedEntity.new(
            :kind => kind, :reference => DeepCopy.call(reference), :entity => entities.last,
            :entities => above.empty? ? model.entities : Group.contents(above.last),
            :transform => above.reduce(Geom::Transformation.new) { |carried, entity| carried * entity.transformation },
            :parent_path => above.map(&:persistent_id)
          )
        end
      end

      TARGET = Records::ReferenceTarget.new(
        :id => GROUP_KIND, :label => "Piping group", :schema_version => 1, :values => RECORD_KIND.values_schema,
        :occurrence => Target::REFERENCE, :records => Target.method(:entries),
        :validate => ->(record) { RECORD_KIND.problems(record) }, :references => RECORD_KIND.references,
        :locate => Target.method(:locate), :locate_index => ->(_model) { Zones::ChildLookup.new }
      )
    end
  end
end
