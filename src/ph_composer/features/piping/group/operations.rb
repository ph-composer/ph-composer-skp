# frozen_string_literal: true

module PhComposer
  module Piping
    module Group
      # Create, link and unlink Piping groups, the retarget a Hot Water System delete asks for, and the occurrence
      # rows the reads return. A write resolves every Group before proposing anything and refuses the whole command
      # if one is stale, unwritable or misplaced; the dispatcher owns the native operation.
      module Operations
        CONTAINMENT = "ph_composer.zones.containment"
        SYSTEM_KIND = Mechanical::HOT_WATER_SYSTEM_KIND
        # One link or unlink names at most this many Groups.
        TARGET_LIMIT = 250
        STRANDED_DETAIL = 20

        module_function

        # One empty Group at the Model root carrying a new record naming the System, opened for drawing.
        def create(request, proposal, hot_water_system_id:)
          request.engine.find(SYSTEM_KIND, hot_water_system_id)
          id = Records::Identity.allocator(request, request.params).call("ppg")
          record = Group.validate!(Group.new_record(id, hot_water_system_id))
          proposal.add_step(LineGroups::CreateStep.new(:spec => LINE_GROUP, :record => record),
                            :scopes => [PhComposer::Operations::EntityScope.new([])])
          { "group_id" => id }
        end

        # Sets each Group's System, or clears it with nil. A Group already naming it is left alone.
        def link(request, proposal, targets:, hot_water_system_id:)
          request.engine.find(SYSTEM_KIND, hot_water_system_id) if hot_water_system_id
          by_path = targets.group_by { |target| target.dig("reference", "group_path") }
          if by_path.values.any? { |repeats| repeats.uniq.length > 1 }
            raise CodedError.new("params.invalid", "Repeated Piping group targets disagree on identity or values.")
          end

          unique = by_path.values.map(&:first)
          if unique.length > TARGET_LIMIT
            raise CodedError.new("gesture.too_large", "One command names at most #{TARGET_LIMIT} Piping groups.")
          end

          located = unique.map do |target|
            group = request.locate(GROUP_KIND, target.fetch("reference")).entity
            before = STORE.read(group)
            check_expected!(before, target.fetch("expected_values", {}))
            [target.fetch("reference"), before]
          end
          outside_zones!(request, located.map { |reference, _before| reference.fetch("group_path") })
          updates = located.filter_map do |reference, before|
            after = Group.validate!(before.merge("hot_water_system_id" => hot_water_system_id))
            { "reference" => reference, "before" => before, "after" => after } unless after == before
          end
          propose(proposal, updates)
          { "group_ids" => updates.map { |update| update.fetch("after").fetch("id") } }
        end

        # The retargeter a Hot Water System delete runs: every Piping group naming `from` names `to`, or none with
        # nil, in the delete's proposal. A group the rewrite cannot reach refuses the delete.
        def retarget(request, proposal, from:, to:)
          updates = []
          stranded = []
          Target.each_group(request.model) do |group, path, _along|
            record, = Group.read(group)
            next unless record && record["hot_water_system_id"] == from

            reference = { "group_id" => record["id"], "group_path" => path }
            begin
              request.locate(GROUP_KIND, reference)
              updates << { "reference" => reference, "before" => record,
                           "after" => Group.validate!(record.merge("hot_water_system_id" => to)) }
            rescue CodedError => error
              stranded << { "group_path" => path, "reason" => error.code }
            end
          end
          refuse_stranded(from, stranded) unless stranded.empty?

          propose(proposal, updates)
          Records::ReferencePlan.new(:entries => updates.map do |update|
            Records::ReferenceEntry.new(:kind => GROUP_KIND, :key => update.dig("reference", "group_path"),
                                        :record => update.fetch("after"))
          end)
        end

        def refuse_stranded(from, stranded)
          message = "#{stranded.length} Piping group(s) name Hot Water System #{from} where the delete cannot " \
                    "rewrite them (locked, shared or nested); unlock, make unique or move them, then delete again."
          raise CodedError.new("reference.in_use", message, "target_kind" => SYSTEM_KIND, "id" => from,
                                                            "groups" => stranded.first(STRANDED_DETAIL),
                                                            "stranded" => stranded.length)
        end

        # Refuses piping.group_in_zone when Zones says a Zone holds any of these root-to-Group paths.
        def outside_zones!(request, paths)
          held = contained(request, paths.uniq).find { |row| row["zone"] }
          return unless held

          raise CodedError.new(Codes::GROUP_IN_ZONE, "Piping group #{held.fetch('path').last} sits inside Zone " \
                                                     "#{held.dig('zone', 'name')}; move it out of the Zone first.")
        end

        def contained(request, paths)
          paths.each_slice(Pages::MAXIMUM_LIMIT).flat_map do |slice|
            request.query(CONTAINMENT, "paths" => slice).fetch("paths")
          end
        end

        def check_expected!(before, expected)
          values = Group.values(before)
          changed = expected.keys.reject { |key| values[key] == expected[key] }
          return if changed.empty?

          raise CodedError.new("target.changed", "The Piping group changed since it was read (#{changed.join(', ')}).")
        end

        def propose(proposal, updates)
          return if updates.empty?

          scopes = updates.map { |update| update.dig("reference", "group_path")[0...-1] }.uniq.map do |path|
            PhComposer::Operations::EntityScope.new(path)
          end
          proposal.add_step(LineGroups::GroupWriteStep.new(:spec => LINE_GROUP, :updates => updates), :scopes => scopes)
        end

        # Every Piping group occurrence in root-path order, with its System, its pipe count, whether its id is
        # copied, its placement findings and the refusal a write to it meets.
        def rows(request)
          found = []
          Target.each_group(request.model) { |group, path, along| found << [group, path, along] }
          reads = found.map { |group, _path, _along| Group.read(group) }
          counts = reads.filter_map { |record, _problem| record && record["id"] }.tally
          zones = contained(request, found.map { |_group, path, _along| path })
          found.zip(reads, zones).map do |(group, path, along), (record, problem), zone|
            row(group, path, along, record, problem, :copied => counts.fetch(record && record["id"], 0) > 1,
                                                     :zone => zone["zone"])
          end.sort_by { |row| row.fetch("path") }
        end

        def row(group, path, along, record, problem, copied:, zone:)
          id = Group.identity(record)
          findings = []
          findings << Codes::GROUP_IN_ZONE if zone
          findings << Codes::GROUP_NESTED if Target.nested_refusal(along[0...-1])
          { "path" => path, "reference" => id && { "group_id" => id, "group_path" => path }, "name" => group.name.to_s,
            "values" => Group.values(record), "pipe_count" => Assignment.pipes_in(group), "copied" => copied,
            "findings" => findings,
            "record_problem" => problem || (record && RECORD_KIND.problems(record).first),
            "write_refusal" => Target.write_refusal(along) }
        end
      end
    end
  end
end
