# frozen_string_literal: true

module PhComposer
  module Programs
    # A Building Segment's occupancy settings that name one of PH-Composer's unwritten defaults: the residential
    # default Program or the default Equipment Set (context/CONTRACTS.md, "Occupancy"). Zones checks each settings
    # payload's references as it stages it, and a stored record never names an unwritten default (Store), so this
    # feature's contributor to `ph_composer.zones.segment_settings_saving` stores the default's bundle first, in the
    # same Undo step, as the assign actions do for a Zone. An id that names no record is left for Zones to refuse.
    module SegmentDefaults
      NAME = "#{FEATURE_ID}.segment_defaults"
      SAVING_TRANSITION = Zones::Options::SegmentSettings::SAVING
      REFUSES = (Zones::ExtensionStaging::REFUSES + %w[validation.failed reference.invalid target.ambiguous
                                                       record.unreadable]).uniq.freeze
      KIND_OF = Store::BUNDLES.values.flatten(1).to_h { |kind, record| [record.fetch("id"), kind] }.freeze

      module_function

      def install(feature)
        feature.transition_contributor(NAME, :transition => SAVING_TRANSITION,
                                             :refuses => REFUSES) do |request, proposal, description|
          payload = description.fetch("extension_payloads")[Occupancy::SEGMENT_NAMESPACE]
          payload.is_a?(Hash) ? store_named(request, proposal, payload) : []
        end
      end

      # Stores every unwritten default `payload` names; answers each record written as a reference.
      def store_named(request, proposal, payload)
        targets = Occupancy::SEGMENT_FIELDS.filter_map do |key|
          kind = Occupancy::TARGETS[key]
          kind && payload[key].is_a?(String) && [kind, payload[key]]
        end
        Store.materialize!(request, proposal, targets).map { |id| { "kind" => KIND_OF.fetch(id), "id" => id } }
      end
    end
  end
end
