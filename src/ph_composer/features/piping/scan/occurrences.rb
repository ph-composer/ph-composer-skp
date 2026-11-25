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
      # `{ path, code, message }` (LineGroups::Scan.edges, which says what `zones` and `walked` do).
      def call(request, zones: true, walked: walk(request.model))
        edges, unreadable = LineGroups::Scan.edges(LINE_GROUP, request, :zones => zones, :walked => walked)
        [edges.map { |edge| fact(edge) }, unreadable]
      end

      # Every readable Piping group occurrence, and the groups that cannot be read (LineGroups::Scan.walk).
      def walk(model)
        LineGroups::Scan.walk(LINE_GROUP, model)
      end

      def fact(edge)
        record = edge.record
        Runs::Fact.new(:path => edge.path, :group => edge.group, :record_id => record.fetch("id"),
                       :pipe_type_id => record.fetch("pipe_type_id"), :role => record.fetch("role"),
                       :values => record.slice(*Assignment::ROLE_VALUES.fetch(record.fetch("role")).keys),
                       :points_m => edge.points_m, :vertex_ids => edge.vertex_ids, :shared => edge.shared)
      end
      private_class_method :fact
    end
  end
end
