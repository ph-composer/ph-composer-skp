# frozen_string_literal: true

module PhComposer
  module Piping
    module Runs
      # What the export writes and says about the runs, worked out once in pure Ruby so the export contributor (over
      # the snapshot) and its preflight (over the live Model) give the same records, codes and objects.
      #
      # One record per Hot Water System whose Piping groups hold pipes, as honeybee-ph's PhHotWaterSystem takes them
      # (honeybee_phhvac/hot_water_piping.py in the pinned wheel): each trunk run with its multiplier, its demand
      # recirculation and the branch runs that hang from it, each branch with the twig runs that hang from it (its
      # `fixtures`), and each recirculation run as one pipe element. A run hangs from its `parent`, the candidate whose
      # identifier sorts first. Every pipe is one segment carrying its Pipe Type's values; distribution pipes run at
      # honeybee-ph's 60 C for 24 h, and a recirculation pipe at its assignment's values. The record also carries the
      # System's recirculation temperature and hours as Recirculation works them out, which the Python section's
      # conformance holds the reloaded system to.
      module Extraction
        # honeybee-ph's pipe segment defaults for what no record sets: a distribution pipe's water temperature and
        # hours a day, and the insulation conductivity of a bare Pipe Type that names none.
        DISTRIBUTION_TEMPERATURE_C = 60.0
        DISTRIBUTION_PERIOD = 24
        DEFAULT_CONDUCTIVITY = 0.04
        # A segment's values from its Pipe Type, as honeybee-ph names them.
        TYPE_VALUES = { "material" => "material", "diameter_mm" => "diameter_mm",
                        "insulation_thickness_mm" => "insulation_thickness_mm",
                        "insulation_reflective" => "insulation_reflective",
                        "insulation_quality" => "insulation_quality" }.freeze

        module_function

        # Every finding over `runs` (Tree.call's), each as `{ "code", "object_id", "message", "blocks_export",
        # "locate" }`, `locate` being runs.locate's params or nil: each run's, under its identifier, then
        # `piping.system_unexported` under each System with pipes that `exported`, the ids of the Systems an exported
        # Zone names, leaves out. `types` maps a Pipe Type id to its record and `systems` a Hot Water System id to its.
        def findings(runs, types:, systems:, exported:)
          found = runs.flat_map do |run|
            Findings.call(run, :types => types, :system_ids => systems.keys).map do |finding|
              finding.merge("object_id" => run.identifier, "message" => named(run, finding.fetch("message")))
            end
          end
          found + (piped(runs, systems) - exported).map do |id|
            { "code" => Codes::SYSTEM_UNEXPORTED, "object_id" => id, "blocks_export" => false, "locate" => nil,
              "message" => "Hot Water System #{systems.fetch(id).fetch('name')} serves no exported Zone, so its " \
                           "pipes are not exported." }
          end
        end

        # One record per System with pipes, in id order. Call it only once `findings` has nothing blocking: every
        # run's Pipe Type exists. `user_data` maps a pipe's path to the user_data its segment carries.
        def records(runs, types:, systems:, user_data: {})
          piped(runs, systems).map do |id|
            mine = runs.select { |run| run.hot_water_system_id == id }
            children = mine.group_by(&:parent)
            element = ->(run) { element(run, types.fetch(run.pipe_type_id), user_data) }
            recirculation = mine.select { |run| run.role == "recirculation" }
            sum = Recirculation.call(recirculation)
            { "id" => id, "system_id" => id,
              "recirculation_temperature_c" => sum.fetch("recirculation_temperature_c"),
              "recirculation_hours" => sum.fetch("recirculation_hours"),
              "trunks" => mine.select { |run| run.role == "trunk" }.map do |trunk|
                element.call(trunk).merge(
                  # A whole float, which a schema "integer" admits, leaves as the integer honeybee-ph's multiplier is.
                  "multiplier" => trunk.values.fetch("multiplier").to_i,
                  "demand_recirculation" => trunk.values.fetch("demand_recirculation"),
                  "branches" => children.fetch(trunk.identifier, []).map do |branch|
                    element.call(branch).merge("twigs" => children.fetch(branch.identifier, []).map(&element))
                  end
                )
              end,
              "recirculation" => recirculation.map(&element) }
          end
        end

        # A finding's message naming its run, once.
        def named(run, message)
          message.start_with?("#{run.display_name} ") ? message : "#{run.display_name}: #{message}"
        end

        # The ids of the existing Systems whose groups hold runs, sorted.
        def piped(runs, systems)
          runs.map(&:hot_water_system_id).select { |id| systems.key?(id) }.uniq.sort
        end

        # One run as one pipe element: its identifier, display name and a segment per pipe in run order.
        def element(run, type, user_data)
          identifiers = run.segments
          segments = run.facts.each_with_index.map do |fact, index|
            segment(identifiers.fetch(index), run.points_m[index, 2], fact, type, user_data.fetch(fact.path, {}))
          end
          { "identifier" => run.identifier, "display_name" => run.display_name, "segments" => segments }
        end

        # One pipe as honeybee-ph's PhHvacPipeSegment takes it, its display name its identifier as honeybee-ph's
        # default is, its points in world metres in run order.
        def segment(identifier, points, fact, type, user_data)
          recirculating = fact.role == "recirculation"
          { "identifier" => identifier, "display_name" => identifier, "points_m" => points }
            .merge(TYPE_VALUES.to_h { |key, field| [key, type.fetch(field)] })
            .merge("insulation_conductivity" => type["insulation_conductivity_w_mk"] || DEFAULT_CONDUCTIVITY,
                   "water_temp_c" => recirculating ? fact.values.fetch("water_temp_c") : DISTRIBUTION_TEMPERATURE_C,
                   "daily_period" => recirculating ? fact.values.fetch("daily_period") : DISTRIBUTION_PERIOD,
                   "user_data" => DeepCopy.call(user_data))
        end
      end
    end
  end
end
