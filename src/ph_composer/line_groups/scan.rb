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
      # One assigned Edge occurrence, detached, its record read and checked: `path` is root to Edge; `group` is its line
      # group occurrence as `{ "group_id", "group_path", "name", <link_key>, "in_zone" }`; `points_m` are its two world
      # endpoints in metres and `vertex_ids` its two vertices' persistent ids, in the same order; `shared` as the
      # occurrence's.
      Edge = Struct.new(:path, :group, :record, :points_m, :vertex_ids, :shared, keyword_init: true)

      module_function

      # Every readable assignment of every readable occurrence as an Edge, and the group and Edge records that cannot be
      # read, each as `{ path, code, message }`, sorted by path. A record failing its schema, another schema version
      # included, is unreadable; an Edge whose group cannot be read is not read. With `zones`, the spec's containment
      # query says which groups a Zone holds, which only findings read; without it no group is held, so a read that
      # reports no finding does not refuse for an unreadable Zone record. `walked` is a `walk` the caller already made.
      def edges(spec, request, zones: true, walked: walk(spec, request.model))
        groups, unreadable = walked
        unreadable = unreadable.dup
        held = GroupOperations.contained(spec, request, zones ? groups.map(&:path) : [])
                              .to_h { |row| [row.fetch("path"), !row["zone"].nil?] }
        found = groups.flat_map do |occurrence|
          path = occurrence.path
          group = { "group_id" => occurrence.record.fetch("id"), "group_path" => path, "name" => occurrence.name,
                    spec.link_key => occurrence.record[spec.link_key], "in_zone" => held.fetch(path, false) }
          occurrence.edges.filter_map { |edge| detach(spec, edge, group, occurrence, unreadable) }
        end
        [found, unreadable.sort_by { |row| row.fetch("path") }]
      end

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

      # One Edge's assignment as an Edge, or nil with a row in `unreadable` for a record that is not a valid one.
      def detach(spec, edge, group, occurrence, unreadable)
        path = occurrence.path + [edge.persistent_id]
        record, problem = LineGroups.read(edge, spec.edge_store)
        problem ||= spec.edge_record_kind.problems(record).first
        if problem
          unreadable << unreadable_row(path, problem)
          return nil
        end

        vertices = [edge.start, edge.end]
        points = vertices.map { |vertex| FaceCapture.point_m(vertex.position.transform(occurrence.transform)) }
        Edge.new(:path => path, :group => group, :record => record, :points_m => points,
                 :vertex_ids => vertices.map(&:persistent_id), :shared => occurrence.shared)
      end

      # Component storage, or a Group whose definition another Group shares: geometry every placement of it shows,
      # counted per placement.
      def shared?(entity)
        return true if entity.is_a?(Sketchup::ComponentInstance)

        definition = entity.respond_to?(:definition) ? entity.definition : nil
        definition.respond_to?(:instances) && definition.instances.length > 1
      end
      private_class_method :read_group, :detach, :shared?
    end
  end
end
