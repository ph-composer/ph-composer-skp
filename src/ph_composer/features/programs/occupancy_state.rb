# frozen_string_literal: true

module PhComposer
  module Programs
    # What occupancy is read from: each Zone with its Segment and assignment (through Zones' public read), each
    # Building Segment with its category and occupancy settings, and each Dwelling. Actions read it before they
    # stage anything; the Single dwelling transition reads its Segment as the proposal leaves it.
    module OccupancyState
      ZONES = "ph_composer.zones.all"

      Zone = Struct.new(:id, :reference, :name, :segment_id, :assignment, keyword_init: true)
      Segment = Struct.new(:id, :name, :category, :settings, :stored, keyword_init: true) do
        # Single dwelling as it applies: on, and a residential Segment (context/CONTRACTS.md, "Occupancy").
        def single?
          settings.fetch("single_dwelling") && category == "residential"
        end
      end
      State = Struct.new(:zones, :segments, :dwellings, keyword_init: true) do
        def zone(id)
          zones.find { |zone| zone.id == id }
        end

        def segment(id)
          segments.find { |segment| segment.id == id }
        end

        def dwelling(id)
          dwellings.find { |dwelling| dwelling.fetch("id") == id }
        end

        def zones_in(segment_id)
          zones.select { |zone| zone.segment_id == segment_id }
        end

        # The Zones whose assignment names `dwelling_id`, single-dwelling Segments' Zones left out: there the
        # setting decides.
        def dwelling_zones(dwelling_id)
          zones.select do |zone|
            zone.assignment.fetch("dwelling_id") == dwelling_id && !segment(zone.segment_id)&.single?
          end
        end
      end

      module_function

      def read(request, proposal: nil)
        catalog = request.registry.catalog
        zones = request.query(ZONES).fetch("zones").map do |row|
          Zone.new(:id => row.fetch("id"), :reference => row.fetch("reference"), :name => row.dig("values", "name"),
                   :segment_id => row.dig("values", "building_segment_id"),
                   :assignment => Occupancy.zone_values(row.fetch("extension_data", {}), catalog))
        end
        segments = request.engine.ids(Occupancy::SEGMENT_KIND).sort.map do |id|
          segment(request.engine.find(Occupancy::SEGMENT_KIND, id, :change_set => proposal), catalog)
        end
        dwellings, = DefinitionLists.read(request.engine, DWELLING_KIND, request.engine.ids(DWELLING_KIND).sort)
        State.new(:zones => zones, :segments => segments, :dwellings => dwellings)
      end

      def segment(record, catalog)
        data = record.fetch("extension_data", {})
        certification = Occupancy.payload(data, Certification::Segment::NAMESPACE, catalog)
        Segment.new(:id => record.fetch("id"), :name => record.fetch("name"),
                    :category => Certification::Segment.values(certification).fetch("category"),
                    :settings => Occupancy.segment_values(data, catalog),
                    :stored => !Occupancy.payload(data, Occupancy::SEGMENT_NAMESPACE, catalog).nil?)
      end
    end
  end
end
