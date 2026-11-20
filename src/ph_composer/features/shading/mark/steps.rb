# frozen_string_literal: true

module PhComposer
  module Shading
    module Mark
      # Every mark one assign or clear writes or removes, in one step, so a command over forty entities is one
      # Undo entry and an all-or-nothing apply. Each update holds a root-to-entity path, whether the entity was
      # marked when the command was planned, and the change: "created" writes the mark, "removed" deletes it.
      class WriteStep
        attr_reader :affected

        def initialize(updates:)
          @updates = updates.map { |update| DeepCopy.call(update).freeze }.freeze
          @affected = @updates.map do |update|
            { "kind" => "shading_mark", "change" => update.fetch("change"),
              "reference" => { "entity_path" => update.fetch("entity_path") } }
          end
        end

        def descriptor
          { "name" => "shading_marks", "updates" => @updates }
        end

        # Resolve every entity and check it is as planned before writing any, so a change since planning aborts
        # the command rather than leaving half of it written.
        def apply(model, _slots)
          resolved = @updates.map do |update|
            entity = Targets.resolve!(model, update.fetch("entity_path")).last
            unless Mark.marked?(entity) == update.fetch("marked")
              raise CodedError.new("target.changed", "An entity's shading mark changed after the command was planned.")
            end

            [entity, update.fetch("change")]
          end
          resolved.each { |entity, change| change == "created" ? Mark.write(entity) : Mark.delete(entity) }
        end
      end
    end
  end
end
