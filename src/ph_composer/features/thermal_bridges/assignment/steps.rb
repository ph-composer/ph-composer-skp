# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    module Assignment
      # Every Edge one command writes, in one step, so an assign over forty Edges is one Undo entry and an
      # all-or-nothing apply. An update with no `after` removes the Edge's assignment.
      class WriteStep
        attr_reader :affected

        def initialize(updates:)
          @updates = updates.map { |update| DeepCopy.call(update).freeze }.freeze
          @affected = @updates.map do |update|
            record = update["after"] || update.fetch("before")
            { "kind" => "edge", "id" => record.fetch("id"), "change" => update.fetch("change"),
              "reference" => update.fetch("reference").merge("entity_id" => update["after"]&.fetch("id")) }
          end
        end

        def descriptor
          { "name" => "thermal_bridge_edges", "updates" => @updates }
        end

        def temporary_ids
          @updates.reject { |update| update.fetch("before") }.map { |update| update.fetch("after").fetch("id") }
        end

        # Resolve and check every Edge before writing any: an Edge that changed since planning aborts the
        # command rather than leaving half of it written. The index is safe because nothing is written
        # until every target has resolved.
        def apply(model, _slots)
          index = Target.index(model)
          resolved = @updates.map do |update|
            located = Target.locate(model, update.fetch("reference"), :mutable => true, :index => index)
            unless STORE.read(located.entity) == update.fetch("before")
              raise CodedError.new("target.changed", "An Edge changed after the command was planned.")
            end

            [located.entity, update]
          end
          resolved.each do |edge, update|
            update["after"] ? STORE.write(edge, update.fetch("after")) : STORE.delete(edge)
          end
        end
      end
    end
  end
end
