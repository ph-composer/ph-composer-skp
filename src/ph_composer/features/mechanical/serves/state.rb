# frozen_string_literal: true

module PhComposer
  module Mechanical
    module Serves
      # What Serves reads and writes from: each Zone occurrence with its slots, from one `ph_composer.zones.all`
      # read through Zones' public interface. Two occurrences of a copy not yet made independent share a Zone id and
      # read as two rows.
      module State
        ZONES = "ph_composer.zones.all"
        STAGE = "ph_composer.zones.stage_extension"
        # What that read can answer, and so what every Serves read and action can.
        REFUSES = %w[geometry.invalid record.unreadable target.wrong_kind validation.failed].freeze

        # `values` are the slots, empty where the Zone stores none or one this version does not understand;
        # `status` is the stored payload's status, nil for none.
        Zone = Struct.new(:id, :reference, :name, :segment_id, :left_out, :values, :status, keyword_init: true) do
          def key
            [id, reference.fetch("zone_path")]
          end
        end

        module_function

        def zones(request)
          catalog = request.registry.catalog
          request.query(ZONES).fetch("zones").map do |row|
            values, status = Payload.read(row.fetch("extension_data", {}), catalog)
            stored = row.fetch("values")
            Zone.new(:id => row.fetch("id"), :reference => row.fetch("reference"), :name => stored["name"],
                     :segment_id => stored["building_segment_id"],
                     :left_out => stored["building_segment_id"].nil? && stored["building_segment"].nil?,
                     :values => values, :status => status)
          end
        end

        # Stages each Zone's whole new payload through Zones in `proposal`; answers the changed Zones as reference
        # entries, which a delete's reference plan projects.
        def stage(request, payloads)
          zones = payloads.map { |zone, payload| { "reference" => zone.reference, "payload" => payload } }
          return [] if zones.empty?

          request.participate(STAGE, "namespace" => NAMESPACE, "zones" => zones).fetch("zone_entries")
        end
      end
    end
  end
end
