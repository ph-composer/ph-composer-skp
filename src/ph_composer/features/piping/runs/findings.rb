# frozen_string_literal: true

module PhComposer
  module Piping
    module Runs
      # A run's findings: what keeps its pipes out of an export, and what a user should look at. Each names the Edges
      # it is about with runs.locate's params. A record that cannot be read is not in any run; the scan reports it.
      module Findings
        module_function

        # `types` maps a Pipe Type id to its record, with no key for one that no longer exists; `system_ids` are the
        # Hot Water Systems that exist.
        def call(run, types:, system_ids:)
          found = []
          found.concat(type_findings(run, types))
          found.concat(group_findings(run, system_ids))
          found.concat(tree_findings(run))
          shared = run.facts.select(&:shared)
          unless shared.empty?
            found << finding(Codes::SHARED_DEFINITION, "#{count(shared)} inside a Piping group another placement " \
                                                       "also draws, counted once per placement.",
                             shared.map(&:path), false)
          end
          found
        end

        def type_findings(run, types)
          type = types[run.pipe_type_id]
          if type.nil?
            missing = run.pipe_type_id ? "Pipe Type #{run.pipe_type_id} no longer exists" : "These pipes have no type"
            return [finding(Codes::TYPE_MISSING, "#{missing}; assign a Pipe Type.", run.edge_paths, true)]
          end
          return [] if PipeType.export_blockers(type).empty?

          [finding(Codes::INSULATION_CONDUCTIVITY_MISSING, "#{type.fetch('name')} has insulation and no insulation " \
                                                           "conductivity.", run.edge_paths, true)]
        end

        def group_findings(run, system_ids)
          group = run.group
          found = []
          unless system_ids.include?(group["hot_water_system_id"])
            linked = group["hot_water_system_id"]
            reason = linked ? "names Hot Water System #{linked}, which no longer exists" : "names no Hot Water System"
            found << finding(Codes::GROUP_UNLINKED, "Piping group #{label(group)} #{reason}; link it.",
                             run.edge_paths, true)
          end
          if group["in_zone"]
            found << finding(Codes::GROUP_IN_ZONE, "Piping group #{label(group)} sits inside a Zone; move it out.",
                             run.edge_paths, true)
          end
          found
        end

        # A branch or twig with no parent blocks; one with two warns and takes the first; a trunk no branch touches
        # warns.
        def tree_findings(run)
          case run.role
          when "branch", "twig" then parent_findings(run)
          when "trunk"
            return [] unless run.children.empty?

            [finding(Codes::TRUNK_WITHOUT_BRANCHES, "#{run.display_name} has no branch.", run.edge_paths, false)]
          else []
          end
        end

        def parent_findings(run)
          if run.candidates.empty?
            code, parent = run.role == "branch" ? [Codes::BRANCH_UNCONNECTED,
                                                   "trunk"] : [Codes::TWIG_UNCONNECTED, "branch"]
            return [finding(code, "#{run.display_name} shares no vertex with a #{parent} in its Piping group.",
                            run.edge_paths, true)]
          end
          return [] if run.candidates.length == 1

          names = run.candidates.map(&:display_name).join(" and ")
          [finding(Codes::PARENT_AMBIGUOUS, "#{run.display_name} touches #{names}; it hangs from " \
                                            "#{run.candidates.first.display_name}.", run.edge_paths, false)]
        end

        def label(group)
          name = group["name"].to_s
          name.empty? ? group["group_id"].to_s : name
        end

        def count(facts)
          facts.length == 1 ? "1 pipe is" : "#{facts.length} pipes are"
        end

        def finding(code, message, paths, blocks)
          { "code" => code, "message" => message, "blocks_export" => blocks, "locate" => { "edge_paths" => paths } }
        end
      end
    end
  end
end
