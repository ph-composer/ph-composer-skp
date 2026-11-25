# frozen_string_literal: true

module PhComposer
  module Ducting
    # What keeps ducts out of an export, and what a user should look at. A run's findings each name the ducts they are
    # about with runs.locate's params; a missing run is about a Ventilator and names it with Mechanical's Locate. Pure
    # Ruby: the caller passes the records and the Ventilators that serve a Zone. A record that cannot be read is in no
    # run; the scan reports it.
    module Findings
      module_function

      # `types` maps a Duct Type id to its record, with no key for one that no longer exists; `ventilator_ids` are the
      # Ventilators that exist.
      def call(run, types:, ventilator_ids:)
        found = type_findings(run, types) + group_findings(run, ventilator_ids)
        shared = run.facts.select(&:shared)
        unless shared.empty?
          found << finding(Codes::SHARED_DEFINITION, "#{count(shared)} inside a Ducting group another placement " \
                                                     "also draws, counted once per placement.",
                           shared.map(&:path), false)
        end
        found
      end

      # `ducting.run_missing` for each of `served`, the Ventilators that serve a Zone, with no Outdoor air run or no
      # Exhaust air run among `runs`, by Ventilator id. A Ventilator serving no Zone has Mechanical's finding instead.
      def missing_runs(runs, served:)
        served.to_h do |id|
          missing = Assignment::DIRECTIONS - runs.select { |run| run.ventilator_id == id }.map(&:direction)
          words = missing.map { |direction| Runs::DIRECTION_WORDS.fetch(direction) }.join(" or ")
          [id, missing.empty? ? [] : [{ "code" => Codes::RUN_MISSING, "blocks_export" => false,
                                        "message" => "Serves a Zone and has no #{words} run; METr assumes none.",
                                        "locate" => Mechanical::Locate.row_locate(id, {}) }]]
        end
      end

      def type_findings(run, types)
        type = types[run.duct_type_id]
        if type.nil?
          missing = run.duct_type_id ? "Duct Type #{run.duct_type_id} no longer exists" : "These ducts have no type"
          return [finding(Codes::TYPE_MISSING, "#{missing}; assign a Duct Type.", run.edge_paths, true)]
        end
        return [] if DuctType.export_blockers(type).empty?

        [finding(Codes::INSULATION_CONDUCTIVITY_MISSING, "#{type.fetch('name')} has insulation and no insulation " \
                                                         "conductivity.", run.edge_paths, true)]
      end

      def group_findings(run, ventilator_ids)
        group = run.group
        name = group["name"].to_s
        label = name.empty? ? group["group_id"].to_s : name
        found = []
        unless ventilator_ids.include?(run.ventilator_id)
          linked = run.ventilator_id
          reason = linked ? "names Ventilator #{linked}, which no longer exists" : "names no Ventilator"
          found << finding(Codes::GROUP_UNLINKED, "Ducting group #{label} #{reason}; link it.", run.edge_paths, true)
        end
        if group["in_zone"]
          found << finding(Codes::GROUP_IN_ZONE, "Ducting group #{label} sits inside a Zone; move it out.",
                           run.edge_paths, true)
        end
        found
      end

      def count(facts)
        facts.length == 1 ? "1 duct is" : "#{facts.length} ducts are"
      end

      def finding(code, message, paths, blocks)
        { "code" => code, "message" => message, "blocks_export" => blocks, "locate" => { "edge_paths" => paths } }
      end
      private_class_method :type_findings, :group_findings, :count, :finding
    end
  end
end
