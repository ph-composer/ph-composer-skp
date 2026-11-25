# frozen_string_literal: true

module PhComposer
  module Piping
    module Assignment
      # The native selection as pipe references, over the shared line-group layer (LineGroups::Selection). A read:
      # writes take the references it returns, with the values as read, through pipes.assign and pipes.clear.
      module Selection
        IGNORED_ROWS = LineGroups::Selection::IGNORED_ROWS
        PAGED = "#{FEATURE_ID}.pipes.selection".freeze

        module_function

        def all(request)
          LineGroups::Selection.all(LINE_GROUP, request, **reads(request))
        end

        def page(request)
          LineGroups::Selection.page(LINE_GROUP, request, PAGED, **reads(request))
        end

        # The pipe tool reads an Edge it points at by the same rule.
        def row(parent, edge, read, zone:, counts:)
          LineGroups::Selection.row(LINE_GROUP, parent, edge, read, :zone => zone, :counts => counts)
        end

        def assignable?(row)
          LineGroups::Selection.assignable?(row)
        end

        # The gesture limit and Zones' containment the rows read.
        def reads(request)
          { :limit => Assignment.gesture_edge_limit,
            :contained => ->(paths) { Group::Operations.contained(request, paths) } }
        end
        private_class_method :reads

        def client(session)
          session.feature_state(:piping_selection) { Client.new(session) }
        end

        # The selection route a panel's assign bar drives: read the selection, then one public invoke with the
        # references and values it read, so a stale selection refuses rather than writing.
        class Client
          PREFIX = "#{FEATURE_ID}.pipes".freeze

          def initialize(session)
            @context = API.connect(:session_id => session.id)
            @sequence = 0
          end

          # `role_values` are the role's values to set, such as { "multiplier" => 12 } for a trunk.
          def assign(pipe_type_id, role, role_values = {})
            invoke("assign", { "pipe_type_id" => pipe_type_id, "role" => role }.merge(role_values))
          end

          def clear
            invoke("clear", {})
          end

          private

          def invoke(name, params)
            read = API.query(:context => @context, :name => "#{PREFIX}.selection_all")
            return read unless read["status"] == "completed"

            rows = read.fetch("value").fetch("edges")
            blocked = rows.find { |row| !Selection.assignable?(row) }
            if rows.empty? || blocked
              refusal = blocked&.fetch("write_refusal")
              return { "status" => "refused", "code" => refusal ? refusal.fetch("code") : Codes::OUTSIDE_GROUP,
                       "effect" => "none",
                       "message" => refusal ? refusal.fetch("message") : "Select Edges inside an open Piping group." }
            end

            targets = rows.map { |row|
              { "reference" => row.fetch("reference"), "expected_values" => row["values"] }
            }
            params = params.merge("targets" => targets)
            API.invoke(:context => @context, :name => "#{PREFIX}.#{name}", :params => params,
                       :request => { "sequence" => @sequence += 1, "expected_revision" => read.fetch("revision") })
          end
        end
      end
    end
  end
end
