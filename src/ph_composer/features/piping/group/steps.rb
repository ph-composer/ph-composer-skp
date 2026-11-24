# frozen_string_literal: true

module PhComposer
  module Piping
    module Group
      # Adds one empty Group at the Model root, writes its Piping group record and opens it for drawing, inside the
      # action's one operation, so one Undo removes it and its record together. The path change runs every edit
      # context boundary (EditContext.enter) and joins the operation.
      class CreateStep
        attr_reader :affected

        def initialize(record:)
          @record = DeepCopy.frozen(record)
          @affected = [{ "kind" => "piping_group", "id" => @record.fetch("id"), "change" => "created" }]
        end

        def descriptor
          { "name" => "create_piping_group", "record" => @record }
        end

        def temporary_ids
          [@record.fetch("id")]
        end

        def apply(model, _slots)
          group = model.entities.add_group
          STORE.write(group, @record)
          EditContext.enter(model, [group])
          @affected = [@affected.first.merge("reference" => { "group_id" => @record.fetch("id"),
                                                              "group_path" => [group.persistent_id] })]
        end
      end

      # Every Piping group record one command rewrites, in one step: each Group is resolved and checked against the
      # record planned before any is written, so a change since planning aborts the whole command.
      class WriteStep
        attr_reader :affected

        def initialize(updates:)
          @updates = updates.map { |update| DeepCopy.frozen(update) }.freeze
          @affected = @updates.map do |update|
            { "kind" => "piping_group", "id" => update.fetch("after").fetch("id"), "change" => "updated",
              "reference" => update.fetch("reference") }
          end
        end

        def descriptor
          { "name" => "piping_groups", "updates" => @updates }
        end

        def apply(model, _slots)
          resolved = @updates.map do |update|
            group = Target.locate(model, update.fetch("reference"), :mutable => true).entity
            unless STORE.read(group) == update.fetch("before")
              raise CodedError.new("target.changed", "A Piping group changed after the command was planned.")
            end

            [group, update.fetch("after")]
          end
          resolved.each { |group, after| STORE.write(group, after) }
        end
      end
    end
  end
end
