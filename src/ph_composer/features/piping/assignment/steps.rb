# frozen_string_literal: true

module PhComposer
  module Piping
    module Assignment
      # Every Edge one command writes, in one step, so an assign over forty Edges is one Undo entry and an
      # all-or-nothing apply. An update with no `after` removes the Edge's assignment.
      class WriteStep
        attr_reader :affected

        def initialize(updates:)
          @updates = updates.map { |update| DeepCopy.frozen(update) }.freeze
          @affected = @updates.map do |update|
            record = update["after"] || update.fetch("before")
            { "kind" => "pipe", "id" => record["id"], "change" => update.fetch("change"),
              "reference" => update.fetch("reference").merge("entity_id" => update["after"]&.fetch("id")) }
          end
        end

        def descriptor
          { "name" => "pipes", "updates" => @updates }
        end

        def temporary_ids
          @updates.reject { |update| update.fetch("before") }.map { |update| update.fetch("after").fetch("id") }
        end

        # Resolve and check every Edge before writing any: an Edge that changed since planning aborts the command.
        def apply(model, _slots)
          resolved = @updates.map do |update|
            edge = Target.locate(model, update.fetch("reference"), :mutable => true).entity
            unless STORE.read(edge) == update.fetch("before")
              raise CodedError.new("target.changed", "An Edge changed after the command was planned.")
            end

            [edge, update["after"]]
          end
          resolved.each { |edge, after| after ? STORE.write(edge, after) : STORE.delete(edge) }
        end
      end
    end
  end
end
