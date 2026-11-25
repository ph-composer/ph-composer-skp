# frozen_string_literal: true

module PhComposer
  module Piping
    # The live read behind the schedule. One walk of the Model finds every Piping group occurrence and the pipes
    # directly in it, through Groups and components, once per placement; Zones answers only which group paths a Zone
    # holds. It opens no operation and writes nothing. A record that cannot be read is a row, never a raise.
    module Scan
      MAX_MESSAGE = RecordQueries::MAX_MESSAGE
      # One readable Piping group occurrence as the walk finds it (LineGroups::Scan::Occurrence).
      Occurrence = LineGroups::Scan::Occurrence

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

      # Every readable Piping group occurrence, and the groups that cannot be read (LineGroups::Scan.walk).
      def walk(model)
        LineGroups::Scan.walk(LINE_GROUP, model)
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
        LineGroups::Scan.unreadable_row(path, problem)
      end
      private_class_method :fact, :world_m, :row
    end
  end
end
