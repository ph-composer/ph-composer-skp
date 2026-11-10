# frozen_string_literal: true

require_relative "definition_plan"

module PhComposer
  module Windows
    module Units
      # Areas refer to complete glazed-element openings, including Frames, not glass-only area.
      # Native uncertainty withholds the result rather than subtracting a guessed Type footprint.
      module Areas
        QUERY = "#{FEATURE_ID}.units.glazed_area_by_face"
        SECTION = "#{FEATURE_ID}.unit_areas"
        # Bounded pages of the same table: the Face rows, optionally of some Zones, and the unhosted Units.
        LIST = "#{FEATURE_ID}.units.face_areas.list"
        UNHOSTED = "#{FEATURE_ID}.units.unhosted.list"
        SCOPE = %w[zone_ids zone_paths].freeze

        module_function

        def install(feature, registry)
          face = DeepCopy.call(registry.record_descriptor("ph_composer.zones.faces.face").occurrence_schema)
          area = { "type" => %w[number null], "minimum" => 0, "x-unit" => "m2" }
          row = Shapes.object({ "reference" => face, "gross_area_m2" => area,
                                "glazed_area_m2" => area, "net_opaque_area_m2" => area,
                                "unit_count" => { "type" => "integer", "minimum" => 0 },
                                "findings" => Shapes.list(Shapes::TEXT) })
          result = Shapes.object({ "faces" => Shapes.list(row),
                                   "unhosted_units" => Shapes.list(TARGET.descriptor.occurrence_schema) })
          feature.query(QUERY,
                        :description => "Glazed opening and net opaque area; uncertain geometry withholds values.",
                        :refuses => Refuses::UNIT_READ,
                        :params => Shapes::NONE, :result => result, :examples => [{}]) do |request|
            types = request.engine.ids(TYPE_KIND).to_h { |id| [id, request.engine.find(TYPE_KIND, id)] }
            measure(request.query("ph_composer.zones.faces.all").fetch("faces"),
                    request.query("#{FEATURE_ID}.units.all").fetch("units"), types)
          end
          feature.snapshot_section(SECTION, :query => QUERY)
          install_pages(feature, row, result)
        end

        def install_pages(feature, row, result)
          page = { "next_cursor" => Pages::NEXT_CURSOR, "total" => Pages::TOTAL }
          ids = { "type" => "array", "items" => Shapes::TEXT, "maxItems" => Pages::MAXIMUM_LIMIT,
                  "description" => "Only Faces in occurrences of these Zone ids." }
          paths = { "type" => "array", "items" => { "type" => "array", "items" => { "type" => "integer" } },
                    "maxItems" => Pages::MAXIMUM_LIMIT, "description" => "Only Faces in the Zones at these paths." }
          feature.query(LIST,
                        :description => "One bounded page of #{QUERY}'s Face rows in Zone and Face path order, " \
                                        "optionally of some Zones: gross, glazed opening and net opaque area, " \
                                        "withheld (null, with findings) when the geometry is uncertain.",
                        :refuses => Refuses::UNIT_READ + Refuses::PAGE,
                        :params => Shapes.object({ "zone_ids" => ids, "zone_paths" => paths,
                                                   "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR },
                                                 :optional => SCOPE + Pages::PAGE_KEYS),
                        :result => Shapes.object({ "faces" => Shapes.list(row),
                                                   "unhosted_unit_total" => Pages::TOTAL.merge(
                                                     "description" => "Units on no Zone Face, in the whole Model; " \
                                                                      "#{UNHOSTED} lists them."
                                                   ) }.merge(page)),
                        :examples => [{}, { "zone_ids" => ["zon_Ab12Cd34Ef56"], "limit" => 50 }]) do |request|
            faces(request)
          end
          feature.query(UNHOSTED,
                        :description => "One bounded page of the Window occurrences #{QUERY} counts on no Zone Face, " \
                                        "in path order.",
                        :refuses => Refuses::UNIT_READ + Refuses::PAGE,
                        :params => Shapes.object({ "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR },
                                                 :optional => Pages::PAGE_KEYS),
                        :result => Shapes.object({ "units" => result.dig("properties", "unhosted_units") }.merge(page)),
                        :examples => [{}]) { |request| unhosted(request) }
        end

        def faces(request)
          params = request.params
          table = table(request, LIST)
          rows = table.fetch("faces").select do |row|
            reference = row.fetch("reference")
            (!params.key?("zone_ids") || params["zone_ids"].include?(reference.fetch("zone_id"))) &&
              (!params.key?("zone_paths") || params["zone_paths"].include?(reference.fetch("zone_path")))
          end
          key = ->(row) { row.fetch("reference").values_at("zone_path", "entity_path").flatten }
          page, next_cursor = Pages.bounded(request, LIST, rows.sort_by(&key), :key => key)
          { "faces" => page, "unhosted_unit_total" => table.fetch("unhosted_units").length,
            "next_cursor" => next_cursor, "total" => rows.length }
        end

        def unhosted(request)
          units = table(request, UNHOSTED).fetch("unhosted_units")
          key = ->(reference) { reference.fetch("entity_path") }
          page, next_cursor = Pages.bounded(request, UNHOSTED, units.sort_by(&key), :key => key)
          { "units" => page, "next_cursor" => next_cursor, "total" => units.length }
        end

        # The whole table, as QUERY answers it; a bad limit or cursor refuses before it is measured.
        def table(request, query)
          Pages.limit(request.params)
          Pages.position(request, query)
          request.query(QUERY)
        end

        def measure(faces, units, types)
          grouped = units.select { |unit| unit["host"] }.group_by { |unit| unit.fetch("host") }
          opening_areas = {}
          rows = faces.map do |face|
            items = grouped.fetch(face.fetch("reference"), [])
            findings = items.flat_map { |unit| unit.fetch("findings").map { |row| row.fetch("code") } }
            values = items.map do |unit|
              id = unit.fetch("values").fetch("window_type_id")
              findings << "window.unknown_type" unless types[id]
              opening_areas[id] = opening_area(types[id]) unless opening_areas.key?(id)
              findings << "window_type.geometry_unavailable" if types[id] && opening_areas[id].nil?
              opening_areas[id]
            end
            gross = face.fetch("area_m2")
            glazed = findings.empty? ? values.sum : nil
            net = glazed && gross - glazed
            if net && net < -FaceGeometry::QUANTUM_M**2
              findings << "window.opening_area_exceeds_host"
              net = nil
            end
            { "reference" => DeepCopy.call(face.fetch("reference")), "gross_area_m2" => gross,
              "glazed_area_m2" => glazed, "net_opaque_area_m2" => net && [net, 0.0].max,
              "unit_count" => items.length, "findings" => findings.uniq.sort }
          end
          references = faces.map { |face| face.fetch("reference") }
          { "faces" => rows, "unhosted_units" => units.reject { |unit| references.include?(unit["host"]) }
                                                      .map { |unit| DeepCopy.call(unit.fetch("reference")) } }
        end

        def opening_area(type)
          return nil unless type

          DefinitionPlan.build(type).panes.sum do |pane|
            xs = pane.polygon_m.map(&:first)
            ys = pane.polygon_m.map { |point| point[1] }
            (xs.max - xs.min) * (ys.max - ys.min)
          end
        rescue CodedError
          nil
        end
        private_class_method :opening_area, :install_pages, :faces, :unhosted, :table
      end
    end
  end
end
