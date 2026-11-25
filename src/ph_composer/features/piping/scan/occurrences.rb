# frozen_string_literal: true

module PhComposer
  module Piping
    # The live read behind the schedule. One walk of the Model finds every Piping group occurrence and the pipes
    # directly in it, through Groups and components, once per placement; Zones answers only which group paths a Zone
    # holds. It opens no operation and writes nothing. A record that cannot be read is a row, never a raise.
    module Scan
      # An unreadable record's message can quote stored text of any length; a row is cut here.
      MAX_MESSAGE = RecordQueries::MAX_MESSAGE
      # One readable Piping group occurrence as the walk finds it: its root-to-Group path, record and name, the Edges
      # directly in it carrying a pipe record, the transform mapping its contents to world, and whether another
      # placement draws its storage.
      Occurrence = Struct.new(:path, :record, :name, :edges, :transform, :shared, keyword_init: true)

      module_function

      # The whole schedule over the live Model: every run with its findings, the totals, the System and Pipe Type
      # rows and every record that cannot be read.
      def schedule(request)
        facts, unreadable = call(request)
        Runs::Schedule.call(facts, :types => records(request.engine, PIPE_TYPE_KIND),
                                   :systems => records(request.engine, Mechanical::HOT_WATER_SYSTEM_KIND))
                      .merge("unreadable" => unreadable, "unreadable_total" => unreadable.length)
      end

      # Each Hot Water System's distribution length by role and recirculation sum, for the panel's Systems table:
      # the walk and the tree without the findings.
      def systems(request)
        facts, = call(request, :zones => false)
        { "systems" => Runs::Schedule.system_rows(Runs::Tree.call(facts),
                                                  records(request.engine, Mechanical::HOT_WATER_SYSTEM_KIND)) }
      end

      # Each Pipe Type id's used length, the drawn length of its runs, as the schedule's types rows add it.
      def used_lengths(request)
        facts, = call(request, :zones => false)
        Runs::Tree.call(facts).group_by(&:pipe_type_id).transform_values { |runs| runs.sum(0.0, &:length_m) }
      end

      # Every record of `kind` by id. One that cannot be read refuses the read, as it refuses its own.
      def records(engine, kind)
        engine.ids(kind).to_h { |id| [id, engine.find(kind, id)] }
      end

      # Every readable pipe occurrence as a Runs::Fact, and the group and pipe records that cannot be read, each as
      # `{ path, code, message }`. A pipe whose Piping group cannot be read is not read. With `zones`, Zones says which
      # groups a Zone holds, which only the findings read; without it no group is held, so a read that reports no
      # finding does not refuse for an unreadable Zone record. `walked` is a `walk` the caller already made.
      def call(request, zones: true, walked: walk(request.model))
        groups, unreadable = walked
        unreadable = unreadable.dup
        paths = zones ? groups.map(&:path) : []
        held = Group::Operations.contained(request, paths).to_h { |row| [row.fetch("path"), !row["zone"].nil?] }
        facts = groups.flat_map do |occurrence|
          path = occurrence.path
          detached = { "group_id" => occurrence.record.fetch("id"), "group_path" => path, "name" => occurrence.name,
                       "hot_water_system_id" => occurrence.record["hot_water_system_id"],
                       "in_zone" => held.fetch(path, false) }
          occurrence.edges.filter_map { |edge| fact(edge, detached, occurrence, unreadable) }
        end
        [facts, unreadable.sort_by { |row| row.fetch("path") }]
      end

      # Every readable Piping group occurrence, and the groups that cannot be read. Transforms compose from the root,
      # so a context open or not gives world points (context/SKETCHUP_HOST_BEHAVIOR.md, "Observers and edit
      # contexts").
      def walk(model)
        groups = []
        unreadable = []
        pending = [[model.entities, [], Geom::Transformation.new, false]]
        until pending.empty?
          entities, path, transform, shared = pending.shift
          entities.each do |entity|
            contents = Group.contents(entity)
            next unless contents

            current = path + [entity.persistent_id]
            placed = transform * entity.transformation
            inside = shared || shared?(entity)
            read_group(entity, current, placed, inside, groups, unreadable) if Group.piping_group?(entity)
            pending << [contents, current, placed, inside]
          end
        end
        [groups, unreadable]
      end

      def read_group(entity, path, transform, shared, groups, unreadable)
        record, problem = Group.read(entity)
        problem ||= record && Group::RECORD_KIND.problems(record).first
        return unreadable << row(path, problem) if problem

        edges = entity.entities.select { |child| child.is_a?(Sketchup::Edge) && Assignment::STORE.marks?(child) }
        groups << Occurrence.new(:path => path, :record => record, :name => entity.name.to_s, :edges => edges,
                                 :transform => transform, :shared => shared)
      end

      # One pipe as a fact, or nil with a row in `unreadable` for a record that is not a valid pipe assignment, a
      # record of another schema version included.
      def fact(edge, group, occurrence, unreadable)
        path = occurrence.path + [edge.persistent_id]
        record, problem = Group.read(edge, Assignment::STORE)
        problem ||= Assignment::RECORD_KIND.problems(record).first
        if problem
          unreadable << row(path, problem)
          return nil
        end

        Runs::Fact.new(:path => path, :group => group, :record_id => record.fetch("id"),
                       :pipe_type_id => record.fetch("pipe_type_id"), :role => record.fetch("role"),
                       :values => record.slice(*Assignment::ROLE_VALUES.fetch(record.fetch("role")).keys),
                       :points_m => [edge.start, edge.end].map { |vertex| world_m(vertex, occurrence.transform) },
                       :vertex_ids => [edge.start, edge.end].map(&:persistent_id), :shared => occurrence.shared)
      end

      def world_m(vertex, transform)
        FaceCapture.point_m(vertex.position.transform(transform))
      end

      def row(path, problem)
        { "path" => path, "code" => "record.unreadable", "message" => problem.to_s[0, MAX_MESSAGE] }
      end

      # Component storage, or a Group whose definition another Group shares: geometry every placement of it shows,
      # counted per placement.
      def shared?(entity)
        return true if entity.is_a?(Sketchup::ComponentInstance)

        definition = entity.respond_to?(:definition) ? entity.definition : nil
        definition.respond_to?(:instances) && definition.instances.length > 1
      end
      private_class_method :read_group, :fact, :world_m, :row, :shared?
    end
  end
end
