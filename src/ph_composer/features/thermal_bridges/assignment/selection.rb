# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    module Assignment
      # The native selection as Edge references. A read: writes take the references it returns, with the
      # values as read, through edges.assign and edges.clear.
      module Selection
        # Selected entities that are not Edges are listed up to this many and counted in full.
        IGNORED_ROWS = 50

        module_function

        PAGED = "#{FEATURE_ID}.edges.selection".freeze

        # Each selected Edge under the active path with the Zone holding it, its assignment as stored and the
        # refusal a write to it meets; anything else selected is reported as ignored and never assigned. An
        # Edge no Zone holds has no reference, and its reason says why. An invalid assignment is read, with
        # its first problem, so it can still be cleared.
        def all(request)
          rows, others = rows(request)
          { "edges" => rows }.merge(ignored(others))
        end

        # The same rows a bounded page at a time, in path order. A cursor is bound to the selection as well
        # as the revision, since selecting changes no revision.
        def page(request)
          rows, others = rows(request)
          binding = "#{request.revision}/#{CanonicalJson.digest(rows.map { |row| row.fetch('path') })}"
          page, cursor = Pages.bounded(request, PAGED, rows, :key => ->(row) { row.fetch("path") },
                                                             :revision => binding)
          { "edges" => page, "next_cursor" => cursor, "total" => rows.length }.merge(ignored(others))
        end

        def ignored(others)
          { "ignored" => others.first(IGNORED_ROWS).map do |entity|
            { "persistent_id" => entity.persistent_id, "type" => entity.typename }
          end, "ignored_total" => others.length }
        end

        def rows(request)
          model = request.model
          edges, others = model.selection.to_a.partition { |entity| entity.is_a?(Sketchup::Edge) }
          if edges.length > Assignment.gesture_edge_limit
            raise CodedError.new("gesture.too_large", "Select at most #{Assignment.gesture_edge_limit} Edges; " \
                                                      "#{edges.length} are selected.")
          end

          parent = Array(model.active_path)
          edges = edges.sort_by { |edge| (parent + [edge]).map(&:persistent_id) }
          paths = edges.map { |edge| (parent + [edge]).map(&:persistent_id) }
          records = edges.map { |edge| STORE.read(edge) }
          copied = copied_ids(model, records)
          [Operations.contained(request, paths).zip(records).map { |row, record| row(row, record, copied) }, others]
        end

        def row(containment, record, copied)
          zone = containment.fetch("zone")
          reference = zone && { "zone_id" => zone.fetch("zone_id"), "zone_path" => zone.fetch("zone_path"),
                                "entity_path" => containment.fetch("entity_path"),
                                "entity_id" => Assignment.identity(record) }
          { "path" => containment.fetch("path"), "reference" => reference,
            "zone" => containment.fetch("zone"), "reason" => containment.fetch("reason"),
            "values" => Assignment.values(record), "copied" => !record.nil? && copied.include?(record["id"]),
            "record_problem" => record && Assignment::RECORD_KIND.problems(record).first,
            "write_refusal" => containment.fetch("write_refusal") }
        end

        # The ids among `records` that more than one Edge in the Model carries. A walk of every tagged Edge,
        # so it is skipped when no selected Edge has an assignment.
        def copied_ids(model, records)
          ids = records.compact.map { |record| record["id"] }.compact
          return [] if ids.empty?

          counts = Target.entries(model).map { |entry| entry.record["id"] }.tally
          ids.select { |id| counts.fetch(id, 0) > 1 }
        end
        private_class_method :rows, :row, :copied_ids, :ignored

        # Whether a write can reach the Edge a selection row names: a Zone holds it, through no shared,
        # locked or other Zone storage. The menu and the panel's assign bar both offer only such Edges.
        def assignable?(row)
          !row["reference"].nil? && row["write_refusal"].nil?
        end

        def client(session)
          session.feature_state(:thermal_bridges_selection_menu) { Client.new(session) }
        end

        # The selection route the right-click menu drives: read the selection, then one public invoke with
        # the references and values it read, so a stale selection refuses rather than writing.
        class Client
          PREFIX = "#{FEATURE_ID}.edges".freeze

          def initialize(session)
            @session = session
            @context = API.connect(:session_id => session.id)
            @sequence = 0
          end

          def assign(type_id, quantity: DEFAULT_QUANTITY)
            invoke("assign", ->(count) { "Assigned #{type_name(type_id)} to #{edges(count)}." }) do |targets|
              { "targets" => targets, "thermal_bridge_type_id" => type_id, "quantity" => quantity }
            end
          end

          def clear
            invoke("clear", ->(count) { "Cleared the thermal bridge from #{edges(count)}." }) do |targets|
              { "targets" => targets }
            end
          end

          private

          # `done` words the confirmation from the number of Edges written, as the panel's assign bar does.
          def invoke(name, done)
            read = API.query(:context => @context, :name => "#{PREFIX}.selection_all")
            return show(read) unless read["status"] == "completed"

            rows = read.fetch("value").fetch("edges")
            return show("status" => "refused", "message" => "Select Edges inside a Zone.") if rows.empty?

            # The Edges a write can reach, as the assign bar takes them; with none, why the first cannot be.
            writable = rows.select { |row| Selection.assignable?(row) }
            return show("status" => "refused", "message" => unreachable_message(rows.first)) if writable.empty?

            targets = writable.map do |row|
              { "reference" => row.fetch("reference"), "expected_values" => row.fetch("values") }
            end
            @sequence += 1
            result = API.invoke(:context => @context, :name => "#{PREFIX}.#{name}", :params => yield(targets),
                                :request => { "sequence" => @sequence, "expected_revision" => read.fetch("revision") })
            show(result["status"] == "completed" ? result.merge("message" => done.call(targets.length)) : result)
          end

          def edges(count)
            count == 1 ? "1 Edge" : "#{count} Edges"
          end

          def type_name(type_id)
            read = API.query(:context => @context, :name => "#{FEATURE_ID}.types.all")
            row = read["status"] == "completed" && read.fetch("value").fetch("records").find { |r| r["id"] == type_id }
            row ? row.dig("values", "name") : "the type"
          end

          def unreachable_message(row)
            return "#{row.fetch('write_refusal').fetch('message')} Nothing was written." if row["reference"]

            "A selected Edge is not inside a Zone (#{row.fetch('reason').tr('_', ' ')}). Nothing was written."
          end

          def show(result)
            @session.notice(result.fetch("message"), :tone => result["status"] == "completed" ? :success : :warning)
            Sketchup.status_text = result.fetch("message")
            result
          end
        end
      end
    end
  end
end
