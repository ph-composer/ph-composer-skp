# frozen_string_literal: true

module PhComposer
  module Piping
    module Assignment
      # The native selection as pipe references. A read: writes take the references it returns, with the values as
      # read, through pipes.assign and pipes.clear.
      module Selection
        # Selected entities that are not Edges are listed up to this many and counted in full.
        IGNORED_ROWS = 50
        PAGED = "#{FEATURE_ID}.pipes.selection".freeze

        module_function

        def all(request)
          rows, others = rows(request)
          { "edges" => rows }.merge(ignored(others))
        end

        # The same rows a bounded page at a time, in path order; a cursor is bound to the selection too.
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

        # Each selected Edge under the active path with the Piping group holding it, its assignment as stored and the
        # refusal a write to it meets. An Edge not directly in a Piping group has no reference; its reason says so.
        def rows(request)
          model = request.model
          edges, others = model.selection.to_a.partition { |entity| entity.is_a?(Sketchup::Edge) }
          limit = Assignment.gesture_edge_limit
          if edges.length > limit
            raise CodedError.new("gesture.too_large", "Select at most #{limit} Edges; #{edges.length} are selected.")
          end

          parent = Array(model.active_path)
          group_paths = parent.empty? ? [] : [parent.map(&:persistent_id)]
          zone = Group::Operations.contained(request, group_paths).first
          reads = edges.map { |edge| Group.read(edge, STORE) }
          ids = reads.filter_map { |record, _problem| record && record["id"] }
          counts = ids.empty? ? {} : Target.entries(model).map { |entry| entry.record["id"] }.tally
          found = edges.zip(reads).map do |edge, read|
            row(parent, edge, read, :zone => zone && zone["zone"], :counts => counts)
          end
          [found.sort_by { |row| row.fetch("path") }, others]
        end

        def row(parent, edge, (record, problem), zone:, counts:)
          path = (parent + [edge]).map(&:persistent_id)
          group = parent.last
          base = { "path" => path, "values" => Assignment.values(record),
                   "copied" => counts.fetch(record && record["id"], 0) > 1,
                   "record_problem" => problem || (record && RECORD_KIND.problems(record).first) }
          unless group && Group.piping_group?(group)
            return base.merge("reference" => nil, "group" => nil, "reason" => "outside_group",
                              "write_refusal" => nil)
          end

          group_record, group_problem = Group.read(group)
          base.merge("reference" => { "group_path" => path[0...-1], "entity_path" => path,
                                      "entity_id" => Assignment.identity(record) },
                     "group" => group_record && { "group_id" => group_record["id"], "group_path" => path[0...-1],
                                                  "hot_water_system_id" => group_record["hot_water_system_id"] },
                     "reason" => nil, "write_refusal" => refusal(parent, zone, group_problem || problem))
        end

        # What a write to an Edge in the open Piping group meets: the group nested in another or held by a Zone, a
        # locked or shared step, or text on the group or the Edge that is not a JSON object.
        def refusal(parent, zone, problem)
          nested = Group::Target.nested_refusal(parent[0...-1])
          return nested if nested
          if zone
            return { "code" => Codes::GROUP_IN_ZONE, "message" => "The Piping group sits inside Zone " \
                                                                  "#{zone.fetch('name')}; move it out first." }
          end

          Group::Target.write_refusal(parent) || (problem && { "code" => "record.unreadable", "message" => problem })
        end

        def assignable?(row)
          !row["reference"].nil? && row["write_refusal"].nil?
        end

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
