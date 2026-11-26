# frozen_string_literal: true

module PhComposer
  module LineGroups
    # Wraps loose lines already drawn in one collection in a new Group with its record, so one Undo restores them
    # loose with their ids and dictionaries (context/SKETCHUP_HOST_BEHAVIOR.md, "Making a line group"). The edit path
    # stays where it is: the user opens the group to draw more lines in it.
    class MakeStep
      attr_reader :affected

      def initialize(spec:, record:, parent_path:, edge_ids:)
        @spec = spec
        @record = DeepCopy.frozen(record)
        @parent_path = parent_path.dup.freeze
        @edge_ids = edge_ids.dup.freeze
        @affected = [{ "kind" => spec.group_noun, "id" => @record.fetch("id"), "change" => "created" }]
      end

      def descriptor
        { "name" => "make_#{@spec.group_noun}", "record" => @record, "parent_path" => @parent_path,
          "edge_ids" => @edge_ids }
      end

      def temporary_ids
        [@record.fetch("id")]
      end

      # Each line is found again, still loose, in the open context the plan read; SketchUp deletes a Group left empty
      # at commit, so nothing here adds one.
      def apply(model, _slots)
        unless Array(model.active_path).map(&:persistent_id) == @parent_path
          raise CodedError.new("target.edit_path_changed", "The open edit context changed. Nothing was written.")
        end

        entities = PhComposer::Operations::EntityScope.new(@parent_path).resolve(model)
        children = entities.to_a.group_by(&:persistent_id)
        lines = @edge_ids.map { |id| loose_line(children.fetch(id, [])) }
        raise CodedError.new("params.invalid", "A #{@spec.label} is made from at least one line.") if lines.empty?

        group = entities.add_group(lines)
        @spec.group_store.write(group, @record)
        @affected = [@affected.first.merge("reference" => { "group_id" => @record.fetch("id"),
                                                            "group_path" => @parent_path + [group.persistent_id] })]
      end

      private

      def loose_line(matches)
        line = matches.first
        return line if matches.length == 1 && line.is_a?(Sketchup::Edge) && line.faces.empty?

        raise CodedError.new("target.changed", "A line changed after the #{@spec.label} was planned. Nothing was " \
                                               "written.")
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
