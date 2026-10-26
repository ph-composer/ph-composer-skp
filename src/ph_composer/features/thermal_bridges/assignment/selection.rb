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

        # Each selected Edge under the active path with the Zone holding it, its assignment as stored and the
        # refusal a write to it meets; anything else selected is reported as ignored and never assigned. An
        # Edge no Zone holds has no reference, and its reason says why. An invalid assignment is read, with
        # its first problem, so it can still be cleared.
        def read(request)
          model = request.model
          edges, others = model.selection.to_a.partition { |entity| entity.is_a?(Sketchup::Edge) }
          if edges.length > Assignment.gesture_edge_limit
            raise CodedError.new("gesture.too_large", "Select at most #{Assignment.gesture_edge_limit} Edges; " \
                                                      "#{edges.length} are selected.")
          end

          parent = Array(model.active_path)
          paths = edges.map { |edge| (parent + [edge]).map(&:persistent_id) }
          rows = Operations.contained(request, paths)
          records = edges.map { |edge| STORE.read(edge) }
          copied = copied_ids(model, records)
          ignored = others.first(IGNORED_ROWS).map do |entity|
            { "persistent_id" => entity.persistent_id, "type" => entity.typename }
          end
          { "edges" => rows.zip(records).map { |row, record| row(row, record, copied) }, "ignored" => ignored,
            "ignored_total" => others.length }
        end

        def row(containment, record, copied)
          zone = containment.fetch("zone")
          reference = zone && { "zone_id" => zone.fetch("zone_id"), "zone_path" => zone.fetch("zone_path"),
                                "entity_path" => containment.fetch("entity_path"), "entity_id" => record&.[]("id") }
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
        private_class_method :row, :copied_ids

        def client(session)
          session.feature_state(:thermal_bridges_selection_menu) { Client.new(session) }
        end

        # The selection route a menu or the panel's assign bar drives: read the selection, then one public
        # invoke with the references and values it read, so a stale selection refuses rather than writing.
        class Client
          PREFIX = "#{FEATURE_ID}.edges".freeze

          def initialize(session)
            @session = session
            @context = API.connect(:session_id => session.id)
            @sequence = 0
          end

          def assign(type_id, quantity: DEFAULT_QUANTITY)
            invoke("assign") do |targets|
              { "targets" => targets, "thermal_bridge_type_id" => type_id, "quantity" => quantity }
            end
          end

          def clear
            invoke("clear") { |targets| { "targets" => targets } }
          end

          private

          def invoke(name)
            read = API.query(:context => @context, :name => "#{PREFIX}.selection")
            return show(read) unless read["status"] == "completed"

            rows = read.fetch("value").fetch("edges")
            unreachable = rows.find { |row| row["reference"].nil? }
            return show("status" => "refused", "message" => "Select Edges inside a Zone.") if rows.empty?
            return show("status" => "refused", "message" => unreachable_message(unreachable)) if unreachable

            targets = rows.map do |row|
              { "reference" => row.fetch("reference"), "expected_values" => row.fetch("values") }
            end
            @sequence += 1
            show(API.invoke(:context => @context, :name => "#{PREFIX}.#{name}", :params => yield(targets),
                            :request => { "sequence" => @sequence, "expected_revision" => read.fetch("revision") }))
          end

          def unreachable_message(row)
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
