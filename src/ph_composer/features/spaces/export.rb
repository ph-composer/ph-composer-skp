# frozen_string_literal: true

module PhComposer
  module Spaces
    # The Spaces export section (context/CONTRACTS.md, "Translation sections and artifacts"): one record per
    # Space occurrence, read from the export snapshot and never the live Model, for the Python section that
    # attaches each honeybee-ph Space to its Zone's Room. A Floor Segment's loops are projected onto the
    # horizontal plane at its outer loop's mean height, so the area honeybee-ph reads back is the plan area the
    # metrics use, and each Volume carries its preview prism (Prism) as its geometry. Airflows leave as stored:
    # an absent rate stays absent, and the translation applies the any-set rule.
    #
    # The preflight reports every finding the Spaces read gives a row, with whether it blocks export, where to
    # find it, and the repair its finding names. The contract itself refuses a structure it cannot write.
    module ExportProjection
      SECTION = "#{FEATURE_ID}.export.spaces"
      PREFLIGHT = "#{FEATURE_ID}.export_preflight"
      ZONES_SECTION = "ph_composer.zones.export.zones"
      TOTALS = %w[floor_area_m2 weighted_area_m2 net_volume_m3].freeze
      SCHEDULE = (%w[space_id zone_id zone_name building_segment number name height_m offset_from_zone] + TOTALS +
                  AIRFLOWS).freeze
      # The schedule's columns: heading, field and quantity (nil for text).
      COLUMNS = [["No.", "number", nil], ["Name", "name", nil], ["Floor area", "floor_area_m2", "area"],
                 ["Weighted area (iCFA)", "weighted_area_m2", "area"], ["Height", "height_m", "length"],
                 ["Net volume", "net_volume_m3", "volume"], ["Supply", "v_sup_m3h", "airflow"],
                 ["Extract", "v_eta_m3h", "airflow"], ["Transfer", "v_tran_m3h", "airflow"]].freeze
      # The batch repair a finding's `repair` names: the action, the param its reference goes in, whether the
      # preflight ticks it by default, and its label.
      Repair = Struct.new(:action, :param, :checked, :label, keyword_init: true)
      REPAIRS = {
        "make_independent" => Repair.new(:action => "#{FEATURE_ID}.make_independent", :param => "reference",
                                         :checked => false, :label => "Make the copy independent"),
        "restore_position" => Repair.new(:action => "#{FEATURE_ID}.volumes.restore_position", :param => "volume",
                                         :checked => true, :label => "Restore the Volume's position")
      }.freeze

      module_function

      def install(feature)
        feature.export_contributor(SECTION, :section_version => 1, :preflight => PREFLIGHT,
                                            :requires => [ZONES_SECTION],
                                            :result => {
                                              "space_zone_totals" => [Export::Privacy.fields(%w[zone_id] + TOTALS)],
                                              "space_segment_totals" => [
                                                Export::Privacy.fields(%w[building_segment] + TOTALS)
                                              ],
                                              "space_schedule" => [Export::Privacy.fields(SCHEDULE)]
                                            }, :report => method(:report)) { |reader| records(reader) }
        feature.query(PREFLIGHT, :description => "Spaces export checks: every finding with where it is and its repair.",
                                 :refuses => [], :params => Shapes::NONE, :result => Export::PREFLIGHT_RESULT,
                                 :examples => [{}]) { |request| preflight(request) }
      end

      # The Spaces schedule: per Zone, the table's columns and the Zone's totals, then the totals per
      # Building-Segment, and one line naming any Space drawn off to the side of its Zone. A Space
      # that inherits its Zone's airflow shows "Zone" in its airflow columns.
      def report(result, display_units)
        rows = result.fetch("space_schedule", [])
        return [] if rows.empty?

        headings = COLUMNS.map { |heading, _field, quantity|
          quantity ? unit_heading(heading, quantity, display_units) : heading
        }
        zone_totals = result.fetch("space_zone_totals", []).to_h { |row| [row.fetch("zone_id"), row] }
        html = rows.group_by { |row| [row.fetch("zone_name"), row.fetch("zone_id")] }.map do |(name, zone_id), spaces|
          body = spaces.map { |row|
            COLUMNS.map { |_heading, field, quantity|
              cell(row, field, quantity, display_units)
            }
          }
          body << total_row("Zone total", zone_totals.fetch(zone_id, {}), spaces, display_units)
          Export::ReportHtml.heading(3, name) + Export::ReportHtml.table(headings, body)
        end.join
        by_segment = rows.group_by { |row| row["building_segment"] }
        segments = result.fetch("space_segment_totals", []).map do |row|
          total_row(row.fetch("building_segment"), row, by_segment.fetch(row.fetch("building_segment"), []),
                    display_units)
        end
        unless segments.empty?
          html += Export::ReportHtml.heading(3, "Building-Segments") + Export::ReportHtml.table(headings, segments)
        end
        offset = rows.select { |row| row["offset_from_zone"] }
        unless offset.empty?
          names = offset.map { |row|
            "#{[row['number'], row['name']].reject(&:empty?).join(' ')} (#{row['zone_name']})"
          }
          html += Export::ReportHtml.paragraph("Drawn outside its Zone's extents and exported as drawn, so a viewer " \
                                               "shows it beside the building: #{names.join(', ')}.")
        end
        [Export::ReportHtml.section("Spaces", html)]
      end

      def unit_heading(heading, quantity, display_units)
        "#{heading} (#{PhComposer::Units.label(:quantity => quantity, :system => display_units)})"
      end

      def cell(row, field, quantity, display_units)
        value = row[field]
        return value.to_s unless quantity
        return "Zone" if value.nil? && quantity == "airflow"
        return "" if value.nil?

        format("%.2f", PhComposer::Units.to_display(value, :quantity => quantity, :system => display_units))
      end

      # A total row: the reported area and volume totals, and the airflows summed over its Spaces by the table's
      # rule, a dash while any of them inherits its Zone's airflow.
      def total_row(label, totals, spaces, display_units)
        inheriting = spaces.any? { |row| AIRFLOWS.all? { |key| row[key].nil? } }
        COLUMNS.map do |_heading, field, quantity|
          next label if field == "number"
          next cell(totals, field, quantity, display_units) if TOTALS.include?(field) && totals.key?(field)
          next "" unless AIRFLOWS.include?(field) && !spaces.empty?
          next "\u2014" if inheriting

          cell({ field => spaces.sum { |row| row[field].to_f } }, field, quantity, display_units)
        end
      end

      def preflight(request)
        read = request.query("#{FEATURE_ID}.all")
        findings = []
        repairs = []
        rows = read.fetch("spaces").flat_map do |space|
          [space] + space.fetch("volumes").flat_map { |volume| [volume] + volume.fetch("floor_segments") }
        end
        # A Space, Volume or Floor Segment row, or a stray record, carries its reference: it is located, and
        # offers the repair its finding names.
        located = rows.flat_map { |row| Array(row["findings"]).map { |finding| [finding, row.fetch("reference")] } } +
                  read.fetch("findings").map { |finding| [finding, finding.fetch("reference")] }
        located.each do |finding, reference|
          findings << finding_row(finding, reference, reference_id(reference))
          repair = repair_row(finding, reference)
          repairs << repair if repair
        end
        findings.concat(offset_findings(request.model))
        { "findings" => findings, "repairs" => repairs.uniq { |row| row.fetch("id") } }
      rescue CodedError => error
        { "findings" => [{ "code" => error.code, "section" => SECTION, "object_id" => nil,
                           "message" => error.message, "blocks_export" => true }], "repairs" => [] }
      end

      def finding_row(finding, reference, object_id)
        row = { "code" => finding.fetch("code"), "section" => SECTION, "object_id" => object_id,
                "message" => finding.fetch("message"), "blocks_export" => finding.fetch("blocks_export") }
        reference ? row.merge("locate" => { "name" => "#{FEATURE_ID}.locate",
                                            "params" => { "reference" => reference } }) : row
      end

      # A Space drawn off to the side of its Zone exports as drawn; the preflight says so, without blocking.
      def offset_findings(model)
        zones = Zones::Occurrences.zones(model)
        spaces = Occurrences.scan(model, :strict => false).spaces
        space_paths = spaces.map(&:path)
        spaces.filter_map do |space|
          zone = zones.select { |candidate| space.path[0, candidate.path.length] == candidate.path }
                      .max_by { |candidate| candidate.path.length }
          next unless zone

          # The Zone's own Faces: none inside a Space, whether or not the Space carries the Zone's stamp.
          own = Zones::Occurrences.faces(zone).reject do |face|
            full = zone.path + face.path
            space_paths.any? { |path| full[0, path.length] == path }
          end
          zone_points = own.flat_map { |face| FaceCapture.call(face.entity, face.transform).loops_m.first }
          space_points = space.volumes.flat_map(&:segments).flat_map do |segment|
            FaceCapture.call(segment.entity, segment.transform).loops_m.first
          end
          next unless Extents.outside?(space_points, zone_points)

          finding_row({ "code" => "space.offset_from_zone", "blocks_export" => false,
                        "message" => "#{label(space.record)} is drawn outside its Zone's extents. It exports as " \
                                     "drawn; a viewer shows it beside the building." }, space.reference,
                      space.record.fetch("id"))
        end
      end

      def label(record)
        text = [record["number"], record["name"]].map(&:to_s).reject(&:empty?).join(" ")
        text.empty? ? "A Space" : "Space #{text}"
      end

      def reference_id(reference)
        reference.values_at("space_id", "volume_id", "floor_segment_id").compact.first
      end

      def repair_row(finding, reference)
        repair = REPAIRS[finding["repair"]]
        return unless repair && reference

        { "id" => "#{repair.action}:#{reference.fetch('entity_path').join('/')}", "label" => repair.label,
          "checked" => repair.checked, "action" => repair.action, "params" => { repair.param => reference } }
      end

      def records(reader)
        snapshot = reader.snapshot
        spaces = unique!(snapshot.records(SPACE_STORE.dictionary, :kind => "group"), "Space")
        volumes = unique!(snapshot.records(VOLUME_STORE.dictionary, :kind => "group"), "Volume")
        segments = unique!(snapshot.records(FLOOR_SEGMENT_STORE.dictionary, :kind => "face"), "Floor Segment")
        structure!(spaces, volumes, segments)
        spaces.map do |entry, record|
          Spaces.validate!(SPACE, record)
          zone = Zones::ExportProjection.enclosing_zone(snapshot, entry)
          raise Export::Blocked.new("space.outside_zone", "Space #{record.fetch('id')} is in no Zone.") unless zone

          own = volumes.select { |volume, _| volume.path[0...-1] == entry.path }
          reader.entity_record(record, :fields => %w[name number] + AIRFLOWS, :target_kind => SPACE_KIND,
                                       :path => entry.path, :user_data => true)
                .merge("zone_id" => zone.last.fetch("id"),
                       "offset_from_zone" => offset?(snapshot, zone.first, own, segments),
                       "volumes" => own.map { |volume| volume_record(reader, volume, segments) }
                                       .sort_by { |row| row.fetch("id") })
        end.sort_by { |row| row.fetch("id") }
      end

      # The same rule as the preflight's, from the snapshot: the Space's Floor Segments against the Zone's own Faces.
      def offset?(snapshot, zone_entry, volumes, segments)
        spaces = snapshot.records(SPACE_STORE.dictionary, :kind => "group").map(&:first)
        own = Zones::ExportProjection.zone_faces(snapshot, zone_entry).reject do |face|
          spaces.any? { |space| snapshot.contains?(space, face) }
        end
        zone_points = own.flat_map { |face| face.geometry.loops_m.first }
        space_points = volumes.flat_map do |volume, _|
          segments.select { |segment, _| segment.path[0...-1] == volume.path }
                  .flat_map { |segment, _| segment.geometry.loops_m.first }
        end
        Extents.outside?(space_points, zone_points)
      end

      def volume_record(reader, (entry, record), segments)
        Spaces.validate!(VOLUME, record)
        height = record["avg_ceiling_height_m"]
        unless height
          raise Export::Blocked.new("space.height_missing", "Volume #{record.fetch('id')} has no average clear " \
                                                            "ceiling height.")
        end

        # An empty Volume is a warning, not a block: it leaves with no Floor Segment and no prism.
        own = segments.select { |segment, _| segment.path[0...-1] == entry.path }
        rows = own.map { |segment| segment_record(reader, segment) }.sort_by { |row| row.fetch("id") }
        prisms = Prism.call(own.map { |segment, _| segment.geometry.loops_m }, height)
        reader.entity_record(record, :fields => %w[display_name avg_ceiling_height_m floor_id],
                                     :target_kind => VOLUME_KIND, :path => entry.path, :user_data => true)
              .merge("floor_segments" => rows, "geometry" => prisms.flat_map(&:polygons))
      end

      def segment_record(reader, (entry, record))
        Spaces.validate!(FLOOR_SEGMENT, record)
        reader.entity_record(record, :fields => %w[display_name weighting_factor net_area_factor],
                                     :target_kind => FLOOR_SEGMENT_KIND, :path => entry.path, :user_data => true)
              .merge("loops_m" => projected(entry.geometry.loops_m))
      end

      # Every loop at the outer loop's mean height: the plan the metrics measure.
      def projected(loops_m)
        z = loops_m.first.sum { |point| point[2] } / loops_m.first.length
        loops_m.map { |loop| loop.map { |x, y, _z| [x, y, z] } }
      end

      # A copied identity is two occurrences with one id, which one record cannot stand for.
      def unique!(entries, label)
        repeated = entries.group_by { |_entry, record| record["id"] }.select { |_id, rows| rows.length > 1 }.keys
        unless repeated.empty?
          message = "A #{label} id is carried by a copy: #{repeated.sort.join(', ')}. Make the copy independent."
          raise Export::Blocked.new("space.duplicate_identity", message)
        end

        entries
      end

      # Membership is the parent Group only: a Volume directly in a Space, a Floor Segment directly in a Volume,
      # and no Space inside another.
      def structure!(spaces, volumes, segments)
        space_paths = spaces.map { |entry, _| entry.path }
        nested = space_paths.any? do |inner|
          space_paths.any? { |outer| outer != inner && inner[0, outer.length] == outer }
        end
        raise Export::Blocked.new("space.nested", "A Space is inside another Space.") if nested

        unless volumes.all? { |entry, _| space_paths.include?(entry.path[0...-1]) }
          raise Export::Blocked.new("space.volume_nested", "A Volume is not directly inside a Space.")
        end

        volume_paths = volumes.map { |entry, _| entry.path }
        return if segments.all? { |entry, _| volume_paths.include?(entry.path[0...-1]) }

        raise Export::Blocked.new("space.segment_misplaced", "A Floor Segment is not directly inside a Volume.")
      end
    end
  end
end
