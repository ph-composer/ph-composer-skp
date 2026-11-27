# frozen_string_literal: true

module PhComposer
  module Mechanical
    # The Zones every mechanical export plan works over, each once, and the finding a plan gives. A plan takes plain
    # values, so the export contributor and the preflight build the same Zones, the first from the export reader
    # and the second from the live Serves read, and get the same pairs and findings.
    module ExportZones
      # One Zone, once per Zone id: `segment` names its Building Segment (nil when it is in none) and `segment_id` is
      # that Segment's record (nil for a legacy Zone, which names no record), `exported` says whether the export
      # writes its Room, and `values` are its Serves slots.
      Zone = Struct.new(:id, :name, :segment, :segment_id, :exported, :values, keyword_init: true) do
        def label
          name || id
        end

        # The Zone as a message names it: Zone “<name>”, or Zone <id> with no name.
        def titled
          Records::Names.titled("Zone", name, id)
        end

        def slot(key)
          values.fetch(key)
        end

        # Whether the slot `key` names item `id`: a single slot holds it, a list slot includes it.
        def names?(key, id)
          value = slot(key)
          value.is_a?(Array) ? value.include?(id) : value == id
        end
      end
      # `record_id` is the row's object: a Zone for a Zone's finding, an item for an item's.
      Finding = Struct.new(:code, :record_id, :message, :blocks, keyword_init: true)

      module_function

      # Each Zone once, the first occurrence by path: its slots from the claimed payload when the Zone exports, and
      # from the Zone record when it is left out. Only the claimant of the Serves payload reads it, so this runs
      # inside the Ventilator export's section, whose projection hands it to every other mechanical section.
      def read(reader)
        payloads = reader.entity_projection(Serves::NAMESPACE, Zones::REFERENCE_KIND)
                         .sort_by { |row| row.fetch("path") || [] }.uniq { |row| row.fetch("id") }
                         .to_h { |row| [row.fetch("id"), row.fetch("payload")] }
        reader.section(Zones::ExportProjection::SECTION).sort_by { |row| row.fetch("zone_path") }
              .uniq { |row| row.fetch("zone_id") }.map do |row|
          id = row.fetch("zone_id")
          exported = row.fetch("exported")
          values = exported ? payloads.fetch(id) { Serves::EMPTY.dup } : left_out_values(reader, id)
          Zone.new(:id => id, :name => row.fetch("name"), :segment => row.fetch("building_segment"),
                   :segment_id => row.fetch("building_segment_id"), :exported => exported, :values => values)
        end
      end

      # A payload this version does not understand reads as served by nothing, as the Serves reads answer it: the
      # Zone leaves with its Room either way, and nothing checks what it held.
      def left_out_values(reader, zone_id)
        _entry, record = Zones::ExportProjection.zone_entry(reader, zone_id)
        Serves::Payload.read(record.fetch("extension_data", {}), Serves::Payload::EXTENSION).first
      end

      # The same Zones from the live Serves read (Serves::State), each once, the first occurrence by path.
      def live(serves_zones)
        serves_zones.sort_by { |zone| zone.reference.fetch("zone_path") }.uniq(&:id).map do |zone|
          Zone.new(:id => zone.id, :name => zone.name, :segment => zone.segment, :segment_id => zone.segment_id,
                   :exported => !zone.left_out, :values => zone.values)
        end
      end

      # Per item of a family: serving no Zone, each served Zone the export leaves out, and Zones in more than one
      # Building Segment. `items` maps each stored item's id to its values with its name; `slot` is the family's
      # Serves slot, single or a list, and `label` its item's name, such as "Ventilator".
      def item_findings(exported, left_out, items, slot, label)
        items.keys.sort.flat_map do |id|
          name = items.fetch(id).fetch("name")
          served = exported.select { |zone| zone.names?(slot, id) }
          gone = left_out.select { |zone| zone.names?(slot, id) }
          next [unserved(id, name)] if served.empty? && gone.empty?

          gone.map { |zone| left_out(id, name, zone) } + across_segments(id, name, served, label)
        end
      end

      # Per item of a family PHX reads through a Room's Spaces (supportive devices, exhaust ventilators, heating
      # systems): one finding naming every exported Zone it serves that no Space names, so two Zones sharing a name
      # stay two in the message. Not blocking: the HBJSON carries the item on those Rooms, and PHX reads it only
      # through another Room it serves. `spaced` holds the ids of the exported Zones with a Space; `slot` and `label`
      # are as `item_findings` takes them.
      def spaceless_findings(exported, items, slot, label, spaced)
        items.keys.sort.filter_map do |id|
          name = items.fetch(id).fetch("name")
          bare = exported.select { |zone| zone.names?(slot, id) && !spaced.include?(zone.id) }.map do |zone|
            zone.name ? Records::Names.quoted(zone.name) : zone.id
          end
          next if bare.empty?

          zones = bare.length == 1 ? "Zone #{bare.first}, which has" : "Zones #{bare.join(', ')}, which have"
          article = label.match?(/\A[AEIOU]/) ? "an" : "a"
          Finding.new(:code => Codes::ZONE_WITHOUT_SPACES, :record_id => id, :blocks => false,
                      :message => "#{name} serves #{zones} no Spaces. PHX reads #{article} #{label} through a Room's " \
                                  "Spaces, so a Building Segment's WUFI-Passive and METr model gets #{name} only " \
                                  "through another Room it serves in that Segment. Add Spaces to " \
                                  "#{bare.length == 1 ? 'that Zone' : 'those Zones'}.")
        end
      end

      # The ids of the exported Zones a Space names, from Spaces' export projection: the export's `spaced` for
      # `spaceless_findings`.
      def spaced(reader)
        reader.section(Spaces::ExportProjection::SECTION).select { |row| row.fetch("space_count").positive? }
              .map { |row| row.fetch("zone_id") }
      end

      # The same over the live Model, for the preflight: each Space read under the Zone it names, as the Spaces export
      # counts them, except one that sits inside a Zone the export leaves out, which leaves with that Zone. `zones` are
      # the live Zones and `references` each Zone's occurrence reference by id. Read only while an exported Zone's
      # `slot` names an item. A Spaces read that refuses gives nil, so the plan skips the no-Spaces finding and the
      # family's rows stand: the Spaces preflight reports that refusal under its own section.
      def live_spaced(request, zones, references, slot)
        return [] unless zones.any? { |zone| zone.exported && !zone.slot(slot).empty? }

        gone = zones.reject(&:exported).filter_map { |zone| references[zone.id]&.fetch("zone_path") }
        request.query(Serves::Reads::SPACES).fetch("spaces").filter_map do |space|
          path = Array(space.dig("reference", "entity_path"))
          next if gone.any? { |zone_path| path.length > zone_path.length && path[0, zone_path.length] == zone_path }

          space.dig("zone", "zone_id")
        end.uniq
      rescue CodedError
        nil
      end

      def unserved(id, name)
        Finding.new(:code => Codes::ITEM_UNSERVED, :record_id => id, :blocks => false,
                    :message => "#{name} serves no Zone, so nothing exports it.")
      end

      def left_out(id, name, zone)
        Finding.new(:code => Codes::ZONE_LEFT_OUT, :record_id => id, :blocks => false,
                    :message => "#{name} serves #{zone.titled}, which is in no Building Segment, so the export " \
                                "leaves that Room out.")
      end

      def across_segments(id, name, served, label)
        segments = served.map(&:segment).uniq.sort
        return [] if segments.length < 2

        [Finding.new(:code => Codes::ITEM_ACROSS_SEGMENTS, :record_id => id, :blocks => false,
                     :message => "#{name} serves Zones in #{segments.length} Building Segments " \
                                 "(#{segments.join(', ')}); each Segment's model carries the whole #{label}.")]
      end
    end
  end
end
