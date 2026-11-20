# frozen_string_literal: true

module PhComposer
  module Programs
    # The rows Programs reads answer: each record as stored, or its unwritten default, with what uses it. At this
    # stage a Program and an Equipment Set are used by the Model's defaults and a Schedule by the Programs naming
    # it; Zone assignments and Dwellings join them when they exist.
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

        { "default_id" => Settings.default_id(request.model, kind), "records" => records }
      end

      def row(request, kind, record, stored, context)
        base = view(request, kind, record, stored)
        return base.merge(schedule_uses(record, context.fetch("programs"))) if kind == SCHEDULE_KIND

        default = record.fetch("id") == context.fetch("default_id")
        base.merge("default" => default, "use_count" => default ? 1 : 0)
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
