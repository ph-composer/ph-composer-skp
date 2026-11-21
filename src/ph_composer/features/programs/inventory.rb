# frozen_string_literal: true

module PhComposer
  module Programs
    # The rows Programs reads answer: each record as stored, or its unwritten default, with what uses it: a Program
    # and an Equipment Set by the Model's defaults and the Zone assignments, Segment settings and (for a Set)
    # Dwellings naming it, a Schedule by the Programs naming it, a Dwelling by the Zones whose assignment names it.
    module Inventory
      module_function

      def view(request, kind, record, stored)
        request.engine.view(kind, record).merge("stored" => stored)
      end

      # [rows, unreadable] of `kind`, in id order.
      def rows(request, kind)
        records, unreadable = Store.all(request, kind)
        stored = request.engine.ids(kind)
        context = context(request, kind, records)
        [records.map { |record| row(request, kind, record, stored.include?(record.fetch("id")), context) }, unreadable]
      end

      def context(request, kind, records)
        return { "programs" => Store.all(request, PROGRAM_KIND).first } if kind == SCHEDULE_KIND
        return { "zones" => OccupancyState.read(request).zones } if kind == DWELLING_KIND

        { "default_id" => Settings.default_id(request.model, kind), "records" => records,
          "occupancy" => OccupancyState.read(request) }
      end

      def row(request, kind, record, stored, context)
        base = view(request, kind, record, stored)
        return base.merge(schedule_uses(record, context.fetch("programs"))) if kind == SCHEDULE_KIND

        if kind == DWELLING_KIND
          uses = context.fetch("zones").count { |zone| zone.assignment["dwelling_id"] == record.fetch("id") }
          return base.merge("default" => false, "use_count" => uses)
        end

        default = record.fetch("id") == context.fetch("default_id")
        uses = (default ? 1 : 0) + occupancy_uses(context.fetch("occupancy"), kind, record.fetch("id"))
        base.merge("default" => default, "use_count" => uses)
      end

      # How many Zone assignments, Segment settings and Dwellings name a Program or Equipment Set.
      def occupancy_uses(state, kind, id)
        keys = kind == PROGRAM_KIND ? %w[program_id default_program_id] : %w[equipment_set_id]
        payloads = state.zones.map(&:assignment) + state.segments.map(&:settings)
        payloads.count { |payload| keys.any? { |key| payload[key] == id } } +
          (kind == EQUIPMENT_SET_KIND ? state.dwellings.count { |record| record["equipment_set_id"] == id } : 0)
      end

      # Each load slot of each Program naming `schedule`, and the Schedule's profile.
      def schedule_uses(schedule, programs)
        id = schedule.fetch("id")
        uses = programs.flat_map do |program|
          Program::SLOTS.keys.filter_map do |key|
            section, field = key.split(".")
            next unless program.fetch(section)[field] == id

            { "program_id" => program.fetch("id"), "name" => program.fetch("name"), "slot" => key }
          end
        end
        { "uses" => uses, "use_count" => uses.length,
          "profile" => ScheduleProfile.call(Schedule::KIND.values(schedule)) }
      end

      # Every row, for the panel.
      def all(request, kind)
        rows, unreadable = rows(request, kind)
        { "records" => rows, "unreadable" => unreadable }
      end

      # One bounded page in id order, optionally of `ids` only.
      def list(request, query, kind)
        rows, unreadable = rows(request, kind)
        rows = rows.select { |row| request.params["ids"].include?(row.fetch("id")) } if request.params.key?("ids")
        page, next_cursor = Pages.bounded(request, query, rows, :key => ->(row) { [row.fetch("id")] })
        { "records" => page, "unreadable" => unreadable, "next_cursor" => next_cursor, "total" => rows.length }
      end
    end
  end
end
