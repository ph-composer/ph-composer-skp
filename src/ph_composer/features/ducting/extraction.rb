# frozen_string_literal: true

module PhComposer
  module Ducting
    # What the export writes and says about the runs, worked out once in pure Ruby so the export contributor (over the
    # snapshot) and its preflight (over the live Model) give the same records, codes and objects.
    #
    # One record per Ventilator whose Ducting groups hold ducts, as honeybee-ph's PhVentilationSystem takes them
    # (honeybee_phhvac/ducting.py and ventilation.py in the pinned wheel): each Outdoor air run as a supply
    # PhDuctElement (`duct_type` 1) and each Exhaust air run as an exhaust one (2), every duct one PhDuctSegment with
    # its Duct Type's values in metres. honeybee-ph's element has no quantity, so a run of quantity N is N elements: the
    # first takes the run's identifier and name, copy k its identifier with `-k`, its name with "(k of N)" and its
    # segments' identifiers the same suffix, so a quantity of N exports the lengths and element count N copies of its
    # Ducting group would.
    module Extraction
      # honeybee-ph's `duct_type` for each direction.
      DUCT_TYPES = { "outdoor_air" => 1, "exhaust_air" => 2 }.freeze
      # The record's element list for each direction, as PhVentilationSystem names them less `_ducting`.
      LISTS = { "outdoor_air" => "supply", "exhaust_air" => "exhaust" }.freeze
      # PhDuctSegment's diameter, which a rectangular segment carries and its `shape_type` ignores, and the insulation
      # conductivity a bare Duct Type that names none exports.
      RECTANGULAR_DIAMETER_M = 0.160
      DEFAULT_CONDUCTIVITY = 0.04

      module_function

      # Every finding over `runs` (Runs.call's), each as `{ "code", "object_id", "message", "blocks_export",
      # "locate" }`, `locate` being runs.locate's params or nil: each run's under its identifier; then, under each
      # Ventilator id, `ducting.run_missing` for each existing Ventilator in `exported` (the ids an exported Zone names)
      # missing a direction, and `ducting.ventilator_unexported` for each with ducts that `exported` leaves out. `types`
      # maps a Duct Type id to its record and `ventilators` a Ventilator id to its.
      def findings(runs, types:, ventilators:, exported:)
        found = runs.flat_map do |run|
          Findings.call(run, :types => types, :ventilator_ids => ventilators.keys).map do |finding|
            finding.merge("object_id" => run.identifier, "message" => named(run, finding.fetch("message")))
          end
        end
        served = exported.select { |id| ventilators.key?(id) }.sort
        missing = Findings.missing_runs(runs, :served => served).flat_map do |id, rows|
          rows.map { |row| row.merge("object_id" => id, "locate" => nil) }
        end
        found + missing + (ducted(runs, ventilators) - exported).map do |id|
          { "code" => Codes::VENTILATOR_UNEXPORTED, "object_id" => id, "blocks_export" => false, "locate" => nil,
            "message" => "Ventilator #{ventilators.fetch(id).fetch('name')} serves no exported Zone, so its ducts " \
                         "are not exported." }
        end
      end

      # One record per Ventilator with ducts, in id order, each list's elements in identifier order. Call it only once
      # `findings` has nothing blocking: every run's Duct Type exists. `user_data` maps a duct's path to the user_data
      # its segment carries. The two lengths are each direction's, quantity applied, as the schedule's are.
      def records(runs, types:, ventilators:, user_data: {})
        ducted(runs, ventilators).map do |id|
          mine = runs.select { |run| run.ventilator_id == id }
          record = { "id" => id, "ventilator_id" => id }
          DUCT_TYPES.each_key do |direction|
            along = mine.select { |run| run.direction == direction }
            list = LISTS.fetch(direction)
            record[list] = along.flat_map { |run| elements(run, types.fetch(run.duct_type_id), user_data) }
                                .sort_by { |element| element.fetch("identifier") }
            record["#{list}_length_m"] = along.sum(0.0, &:counted_length_m)
          end
          record
        end
      end

      # A finding's message naming its run, once.
      def named(run, message)
        message.start_with?("#{run.display_name} ") ? message : "#{run.display_name}: #{message}"
      end

      # The ids of the existing Ventilators whose groups hold runs, sorted.
      def ducted(runs, ventilators)
        runs.map(&:ventilator_id).select { |id| ventilators.key?(id) }.uniq.sort
      end

      # One run as `quantity` elements, each with a segment per duct in run order.
      def elements(run, type, user_data)
        segments = run.facts.zip(run.segments).map do |fact, identifier|
          segment(identifier, fact, type, user_data.fetch(fact.path, {}))
        end
        count = run.quantity
        (1..count).map do |copy|
          suffix = copy == 1 ? "" : "-#{copy}"
          { "identifier" => "#{run.identifier}#{suffix}",
            "display_name" => copy == 1 ? run.display_name : "#{run.display_name} (#{copy} of #{count})",
            "duct_type" => DUCT_TYPES.fetch(run.direction),
            "segments" => segments.map do |part|
              renamed = "#{part.fetch('identifier')}#{suffix}"
              part.merge("identifier" => renamed, "display_name" => renamed,
                         "user_data" => DeepCopy.call(part.fetch("user_data")))
            end }
        end
      end

      # One duct as honeybee-ph's PhDuctSegment takes it, in metres, its display name its identifier as honeybee-ph's
      # default is. A Round type gives its diameter and no width or height; a Rectangular type its width and height.
      def segment(identifier, fact, type, user_data)
        round = type.fetch("shape") == "round"
        { "identifier" => identifier, "display_name" => identifier, "points_m" => fact.points_m,
          "diameter_m" => round ? metres(type.fetch("diameter_mm")) : RECTANGULAR_DIAMETER_M,
          "width_m" => round ? nil : metres(type.fetch("width_mm")),
          "height_m" => round ? nil : metres(type.fetch("height_mm")),
          "insulation_thickness_m" => metres(type.fetch("insulation_thickness_mm")),
          "insulation_conductivity" => type["insulation_conductivity_w_mk"] || DEFAULT_CONDUCTIVITY,
          "insulation_reflective" => type.fetch("insulation_reflective"), "user_data" => user_data }
      end

      def metres(millimetres)
        millimetres / 1000.0
      end
      private_class_method :named, :elements, :segment, :metres
    end
  end
end
