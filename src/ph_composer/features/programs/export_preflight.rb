# frozen_string_literal: true

module PhComposer
  module Programs
    # `programs.export_preflight`: the Program export's findings read live, as ExportPlan finds them over the
    # snapshot, and the occupancy reads' findings on the exported Zones and Segments (OccupancyReads), each a
    # warning. Each row's `locate` opens the Zones / Programs view with its Zones checked, or a single dwelling's
    # Building Segment settings, through `programs.locate`. Reads only.
    module ProgramPreflight
      NAME = "#{FEATURE_ID}.export_preflight"
      LOCATE = "#{FEATURE_ID}.locate"
      VIEW = "#{FEATURE_ID}.zones"
      SECTION = "#{FEATURE_ID}.export.rooms"
      SPACES = "ph_composer.spaces.all"
      FACES = "ph_composer.zones.faces.all"
      # A Locate checks at most this many Zones, the view command's limit.
      LOCATE_LIMIT = 500
      # A finding's words in place of a message that would carry a local file path into the export's report.
      PATH_LEFT_OUT = "A name in this finding reads as a local file path, so it is left out here."
      # The occupancy reads' Segment findings; a Segment row also repeats its Zones' findings, read from the Zones.
      SEGMENT_CODES = %w[programs.single_dwelling_no_effect programs.residential_without_dwelling
                         programs.non_residential_dwellings].freeze
      LOCATE_PARAMS = SchemaShapes.object({
        "zones" => { "type" => "array", "items" => Zones::ZONE_REFERENCE, "maxItems" => 500,
                     "description" => "Zones to check in the Zones / Programs view." },
        "building_segment_id" => SchemaShapes.id("bsg", "A Building Segment whose settings dialog opens.")
      }, :optional => %w[zones building_segment_id]).freeze

      module_function

      def install(feature)
        feature.query(NAME, :description => "Program export checks: a Program value missing, set points that " \
                                            "disagree or are inverted, a Phius rule over no Dwelling, counts not " \
                                            "entered, an Equipment Set in a non-residential Segment, and the " \
                                            "occupancy findings on exported Zones.",
                            :refuses => [], :params => SchemaShapes.object({}),
                            :result => PhComposer::Export::PREFLIGHT_RESULT, :examples => [{}]) do |request|
          call(request)
        end
        feature.view_command(LOCATE, :description => "Open the Zones tab on the Programs view with the given Zones " \
                                                     "checked, and a Building Segment's settings dialog when one " \
                                                     "is named.",
                                     :refuses => %w[session.inactive], :params => LOCATE_PARAMS,
                                     :side_effects => "Opens or raises the panel on the Zones tab.",
                                     :result => SchemaShapes.object({ "opened" => { "type" => "boolean" } }),
                                     :examples => [{ "zones" => [{ "zone_id" => "zon_Ab12Cd34Ef56",
                                                                   "zone_path" => [1201] }] }]) do |request|
          locate(request)
        end
      end

      def locate(request)
        intent = { "view" => VIEW }
        zones = request.params.fetch("zones", [])
        intent["zones"] = zones unless zones.empty?
        segment = request.params["building_segment_id"]
        intent["segmentSettings"] = segment if segment
        request.session.open_in_panel("ph_composer.zones", intent)
        { "opened" => true }
      end

      def call(request)
        state = exported(request, OccupancyState.read(request))
        sums = request.query(SPACES).fetch("zones").to_h { |row| [row.fetch("zone_id"), row] }
        floors = floor_areas(request)
        areas = state.zones.to_h do |zone|
          totals = sums.fetch(zone.id, {})
          [zone.id, ExportPlan::Area.new(:floor_area_m2 => totals.fetch("floor_area_m2", 0.0).to_f,
                                         :icfa_m2 => totals.fetch("weighted_area_m2", 0.0).to_f,
                                         :room_floor_area_m2 => floors.fetch(zone.reference.fetch("zone_path"), 0.0))]
        end
        input = ExportPlan::Input.new(:state => state, :catalog => catalog(request), :areas => areas,
                                      :export_identifiers => {})
        rows = ExportPlan.findings(input).map do |finding|
          row(finding.code, finding.record_id, finding.message, finding.blocks,
              locate_params(state, finding.zone_ids, finding.segment_id))
        end
        { "findings" => rows + read_rows(request, state), "repairs" => [] }
      rescue CodedError => error
        # A read this one makes refused, so the export would stop on the same cause: one blocking row says so,
        # and the other contributors' preflights still answer.
        { "findings" => [row(error.code, nil, error.message, true, nil)], "repairs" => [] }
      end

      # Each Zone occurrence's classified Floor Face area, by its path, as the Zones Faces read gives it.
      def floor_areas(request)
        floors = Hash.new(0.0)
        request.query(FACES).fetch("faces").each do |row|
          next unless row.dig("values", "face_type") == "Floor"

          floors[row.dig("reference", "zone_path")] += row.fetch("area_m2").to_f
        end
        floors
      end

      # `state` less the Zones export leaves out with no Building Segment, and their Segments.
      def exported(request, state)
        left_out = Zones::ExportProjection.left_out_zones(request.model).map(&:path)
        zones = state.zones.reject { |zone| left_out.include?(zone.reference.fetch("zone_path")) }
        ids = zones.map(&:segment_id).compact
        OccupancyState::State.new(:zones => zones, :segments => state.segments.select { |row| ids.include?(row.id) },
                                  :dwellings => state.dwellings)
      end

      def catalog(request)
        by_id = lambda do |kind|
          Store.all(request, kind).first.to_h do |record|
            [record.fetch("id"), Store::KINDS.fetch(kind).values(record).merge("id" => record.fetch("id"))]
          end
        end
        defaults = Settings.read(request.model)
        ExportPlan::Catalog.new(:programs => by_id.call(PROGRAM_KIND), :schedules => by_id.call(SCHEDULE_KIND),
                                :equipment_sets => by_id.call(EQUIPMENT_SET_KIND),
                                :default_program_id => defaults.fetch("default_program_id"),
                                :default_equipment_set_id => defaults.fetch("default_equipment_set_id"))
      end

      # The occupancy reads' findings on the exported Zones and their Segments, each a warning. The set points
      # finding is the plan's, which names the pair exported.
      def read_rows(request, state)
        read = OccupancyReads.build(request)
        paths = state.zones.map { |zone| zone.reference.fetch("zone_path") }
        zones = read.fetch(:zones).select { |row| paths.include?(row.dig("reference", "zone_path")) }
        zone_rows = zones.flat_map do |zone|
          zone.fetch("findings").map do |finding|
            row(finding.fetch("code"), zone.fetch("zone_id"), finding.fetch("message"), false,
                locate_params(state, [zone.fetch("zone_id")], nil))
          end
        end
        segments = read.fetch(:segments).select { |segment| state.segment(segment.fetch("id")) }
        zone_rows + segments.flat_map do |segment|
          segment.fetch("findings").select { |finding| SEGMENT_CODES.include?(finding.fetch("code")) }.map do |finding|
            row(finding.fetch("code"), segment.fetch("id"), finding.fetch("message"), false,
                locate_params(state, [], segment.fetch("id")))
          end
        end
      end

      # What a row's Locate opens: its Zones checked, less a single dwelling's, which the Segment's settings decide
      # and whose settings open instead.
      def locate_params(state, zone_ids, segment_id)
        zones = zone_ids.filter_map { |id| state.zone(id) }
        single, checkable = zones.partition { |zone| state.segment(zone.segment_id)&.single? }
        segment_id ||= single.first&.segment_id
        params = {}
        unless checkable.empty?
          params["zones"] = checkable.first(LOCATE_LIMIT).map do |zone|
            DeepCopy.call(zone.reference.slice("zone_id", "zone_path"))
          end
        end
        params["building_segment_id"] = segment_id if segment_id
        params.empty? ? nil : { "name" => LOCATE, "params" => params }
      end

      # One preflight row. A started export's report carries the preflight's warnings, so a message that would
      # carry a local file path is replaced.
      def row(code, object_id, message, blocks, locate)
        message = PATH_LEFT_OUT if Diagnostics.absolute_path?(message)
        found = { "code" => code, "section" => SECTION, "object_id" => object_id, "message" => message,
                  "blocks_export" => blocks }
        locate ? found.merge("locate" => locate) : found
      end
    end
  end
end
