# frozen_string_literal: true

module PhComposer
  module Ducting
    # The live read behind the schedule: the shared layer's walk with Ducting's spec, each duct as a Runs::Fact. It
    # opens no operation and writes nothing; a record that cannot be read is a row, never a raise. Which Ventilators
    # serve a Zone is Mechanical's published read, so nothing here names Mechanical's internals.
    module Scan
      SERVED_READ = "ph_composer.mechanical.ventilators.all"

      module_function

      # The whole schedule over the live Model: every run with its findings, the totals, the Ventilator and Duct Type
      # rows and every record that cannot be read.
      def schedule(request)
        facts, unreadable = call(request)
        engine = request.engine
        served = request.query(SERVED_READ).fetch("records").reject { |row| row.fetch("zones").empty? }
        Schedule.call(facts, :types => records(engine, DUCT_TYPE_KIND),
                             :ventilators => records(engine, Mechanical::VENTILATOR_KIND),
                             :served => served.map { |row| row.fetch("id") })
                .merge("unreadable" => unreadable, "unreadable_total" => unreadable.length)
      end

      # The most Ducting group names one Ventilator row lists; `group_count` counts them all.
      GROUP_NAMES = 20

      # Each Ventilator's two duct lengths, quantity applied, for the Ventilators table: the walk and the runs without
      # findings or Zones, each name cut as a schedule page cuts it; and the Ducting groups linked to it, which its
      # delete leaves unlinked unless a replacement takes them.
      def ventilators(request)
        facts, = call(request, :zones => false)
        rows = Schedule.ventilator_rows(Runs.call(facts), records(request.engine, Mechanical::VENTILATOR_KIND))
        linked = LineGroups::GroupOperations.names_by_link(LINE_GROUP, request.model)
        { "ventilators" => rows.map do |row|
          names = linked.fetch(row.fetch("ventilator_id"), [])
          row.merge(OccurrencePath.bounded_names(row.slice("name")))
             .merge("group_names" => names.first(GROUP_NAMES).map { |name| name[0, OccurrencePath::NAME_CHARACTERS] },
                    "group_count" => names.length)
        end }
      end

      # Each Duct Type id's used length, quantity applied, as the schedule's types rows give it.
      def used_lengths(request)
        facts, = call(request, :zones => false)
        Schedule.used_lengths(Runs.call(facts))
      end

      # Every record of `kind` by id. One that cannot be read refuses the read, as it refuses its own.
      def records(engine, kind)
        engine.ids(kind).to_h { |id| [id, engine.find(kind, id)] }
      end

      # Every readable duct occurrence as a Runs::Fact, and the group and duct records that cannot be read
      # (LineGroups::Scan.edges, which says what `zones` and `walked` do).
      def call(request, zones: true, walked: LineGroups::Scan.walk(LINE_GROUP, request.model))
        edges, unreadable = LineGroups::Scan.edges(LINE_GROUP, request, :zones => zones, :walked => walked)
        [edges.map { |edge| fact(edge) }, unreadable]
      end

      # One LineGroups::Scan::Edge, from the live walk or the export snapshot, as a Runs::Fact.
      def fact(edge)
        record = edge.record
        Runs::Fact.new(:path => edge.path, :group => edge.group, :record_id => record.fetch("id"),
                       :duct_type_id => record.fetch("duct_type_id"), :direction => record.fetch("direction"),
                       :quantity => record.fetch("quantity"), :points_m => edge.points_m, :shared => edge.shared)
      end
    end
  end
end
