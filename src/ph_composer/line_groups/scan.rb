# frozen_string_literal: true

module PhComposer
  module LineGroups
    # One walk of the Model finds every line group occurrence and its assigned Edges, through Groups and components,
    # once per placement. It writes nothing; a record that cannot be read is a row, never a raise.
    module Scan
      # An unreadable record's message can quote stored text of any length; a row is cut here.
      MAX_MESSAGE = RecordQueries::MAX_MESSAGE
      # One readable line group occurrence as the walk finds it: its root-to-Group path, record and name, the Edges
      # directly in it carrying an assignment record, the transform mapping its contents to world, and whether another
      # placement draws its storage.
      Occurrence = Struct.new(:path, :record, :name, :edges, :transform, :shared, keyword_init: true)

      module_function

      # Every readable line group occurrence, and the groups that cannot be read, each as `{ path, code, message }`.
      # Transforms compose from the root, so a context open or not gives world points
      # (context/SKETCHUP_HOST_BEHAVIOR.md, "Observers and edit contexts").
      def walk(spec, model)
        groups = []
        unreadable = []
        pending = [[model.entities, [], Geom::Transformation.new, false]]
        until pending.empty?
          entities, path, transform, shared = pending.shift
          entities.each do |entity|
            contents = LineGroups.contents(entity)
            next unless contents

            current = path + [entity.persistent_id]
            placed = transform * entity.transformation
            inside = shared || shared?(entity)
            read_group(spec, entity, current, placed, inside, groups, unreadable) if spec.group?(entity)
            pending << [contents, current, placed, inside]
          end
        end
        [groups, unreadable]
      end

      # An unreadable record's row, its message cut to MAX_MESSAGE.
      def unreadable_row(path, problem)
        { "path" => path, "code" => "record.unreadable", "message" => problem.to_s[0, MAX_MESSAGE] }
      end

      def read_group(spec, entity, path, transform, shared, groups, unreadable)
        record, problem = LineGroups.read(entity, spec.group_store)
        problem ||= record && spec.group_record_kind.problems(record).first
        return unreadable << unreadable_row(path, problem) if problem

        edges = entity.entities.select { |child| spec.edge?(child) }
        groups << Occurrence.new(:path => path, :record => record, :name => entity.name.to_s, :edges => edges,
                                 :transform => transform, :shared => shared)
      end

      # Component storage, or a Group whose definition another Group shares: geometry every placement of it shows,
      # counted per placement.
      def shared?(entity)
        return true if entity.is_a?(Sketchup::ComponentInstance)

        definition = entity.respond_to?(:definition) ? entity.definition : nil
        definition.respond_to?(:instances) && definition.instances.length > 1
      end
      private_class_method :read_group, :shared?
    end
  end
end
