# frozen_string_literal: true

module PhComposer
  module LineGroups
    # Adds one empty Group at the root with its record and opens it for drawing, so one Undo removes both. The path
    # change runs every edit context boundary (EditContext.enter) and joins the operation.
    class CreateStep
      attr_reader :affected

      def initialize(spec:, record:)
        @spec = spec
        @record = DeepCopy.frozen(record)
        @affected = [{ "kind" => spec.group_noun, "id" => @record.fetch("id"), "change" => "created" }]
      end

      def descriptor
        { "name" => "create_#{@spec.group_noun}", "record" => @record }
      end

      def temporary_ids
        [@record.fetch("id")]
      end

      def apply(model, _slots)
        group = model.entities.add_group
        @spec.group_store.write(group, @record)
        EditContext.enter(model, [group])
        @affected = [@affected.first.merge("reference" => { "group_id" => @record.fetch("id"),
                                                            "group_path" => [group.persistent_id] })]
      end
    end

    # Every line group record one command rewrites, in one step: each Group is resolved and checked against the record
    # planned before any is written, so a change since planning aborts the whole command.
    class GroupWriteStep
      attr_reader :affected

      def initialize(spec:, updates:)
        @spec = spec
        @updates = updates.map { |update| DeepCopy.frozen(update) }.freeze
        @affected = @updates.map do |update|
          { "kind" => spec.group_noun, "id" => update.fetch("after").fetch("id"), "change" => "updated",
            "reference" => update.fetch("reference") }
        end
      end

      def descriptor
        { "name" => "#{@spec.group_noun}s", "updates" => @updates }
      end

      def apply(model, _slots)
        index = @spec.child_lookup.call
        resolved = @updates.map do |update|
          group = GroupTarget.locate(@spec, model, update.fetch("reference"), :mutable => true, :index => index).entity
          unless @spec.group_store.read(group) == update.fetch("before")
            raise CodedError.new("target.changed", "A #{@spec.label} changed after the command was planned.")
          end

          [group, update.fetch("after")]
        end
        resolved.each { |group, after| @spec.group_store.write(group, after) }
      end
    end

    # Every Edge one command writes, in one step, so an assign over forty Edges is one Undo entry and an all-or-nothing
    # apply. An update with no `after` removes the Edge's assignment.
    class EdgeWriteStep
      attr_reader :affected

      def initialize(spec:, updates:)
        @spec = spec
        @updates = updates.map { |update| DeepCopy.frozen(update) }.freeze
        @affected = @updates.map do |update|
          record = update["after"] || update.fetch("before")
          { "kind" => spec.edge_noun, "id" => record["id"], "change" => update.fetch("change"),
            "reference" => update.fetch("reference").merge("entity_id" => update["after"]&.fetch("id")) }
        end
      end

      def descriptor
        { "name" => "#{@spec.edge_noun}s", "updates" => @updates }
      end

      def temporary_ids
        @updates.reject { |update| update.fetch("before") }.map { |update| update.fetch("after").fetch("id") }
      end

      # Resolve and check every Edge before writing any: an Edge that changed since planning aborts the command.
      def apply(model, _slots)
        index = @spec.child_lookup.call
        store = @spec.edge_store
        resolved = @updates.map do |update|
          edge = EdgeTarget.locate(@spec, model, update.fetch("reference"), :mutable => true, :index => index).entity
          unless store.read(edge) == update.fetch("before")
            raise CodedError.new("target.changed", "An Edge changed after the command was planned.")
          end

          [edge, update["after"]]
        end
        resolved.each { |edge, after| after ? store.write(edge, after) : store.delete(edge) }
      end
    end
  end
end
