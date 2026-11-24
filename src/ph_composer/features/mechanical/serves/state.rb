# frozen_string_literal: true

module PhComposer
  module Mechanical
    module Serves
      # What Serves reads and writes from: each Zone occurrence with its slots, from one `ph_composer.zones.all`
      # read through Zones' public interface. Two occurrences of a copy not yet made independent share a Zone id and
      # read as two rows.
      #
      # That read answers the Zones as stored. Inside a proposal, a Zone this feature already staged reads as the
      # proposal leaves it: `stage` keeps each staged payload and Zones' reference entry for it on the request, so a
      # later step of the same proposal (a delete's move after an assign) builds from the staged payload, and the
      # delete's reference plan projects every Zone the proposal rewrites. Only this feature stages its namespace.
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
          payloads = staged(request).fetch(:payloads)
          request.query(ZONES).fetch("zones").map do |row|
            values, status = Payload.read(row.fetch("extension_data", {}), catalog)
            stored = row.fetch("values")
            zone = Zone.new(:id => row.fetch("id"), :reference => row.fetch("reference"), :name => stored["name"],
                            :segment_id => stored["building_segment_id"],
                            :left_out => stored["building_segment_id"].nil? && stored["building_segment"].nil?,
                            :values => values, :status => status)
            if (payload = payloads[zone.key])
              zone.values = DeepCopy.call(payload)
              zone.status = "understood"
            end
            zone
          end
        end

        # Stages each Zone's whole new payload through Zones in the request's proposal and keeps it, with the Zone's
        # reference entry, for the rest of the proposal.
        def stage(request, payloads)
          zones = payloads.map { |zone, payload| { "reference" => zone.reference, "payload" => payload } }
          return if zones.empty?

          entries = request.participate(STAGE, "namespace" => NAMESPACE, "zones" => zones).fetch("zone_entries")
          kept = staged(request)
          payloads.each { |zone, payload| kept.fetch(:payloads)[zone.key] = DeepCopy.call(payload) }
          entries.each { |entry| kept.fetch(:entries)[entry.fetch("key")] = entry }
        end

        # Every Zone this request's proposal has staged a payload on, as reference entries, the latest per Zone.
        def entries(request)
          staged(request).fetch(:entries).values
        end

        def staged(request)
          request.memo(:serves_staged) { { :payloads => {}, :entries => {} } }
        end
      end
    end
  end
end
