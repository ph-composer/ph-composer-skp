# frozen_string_literal: true

module PhComposer
  module Spaces
    # The Spaces export section (context/CONTRACTS.md, "Translation sections and artifacts"): one record per
    # Space occurrence, read from the export snapshot and never the live Model, for the Python section that
    # attaches each honeybee-ph Space to its Zone's Room. A Floor Segment's loops are projected onto the
    # horizontal plane at its outer loop's mean height, so the area honeybee-ph reads back is the plan area the
    # metrics use, and each Volume carries its preview prism (Prism) as its geometry. Airflows leave as stored,
    # an absent rate absent, with each Space's Zone's airflow mode (`airflow_mode`, section version 2), which
    # the translation follows and never derives.
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
        "unhost" => Repair.new(:action => "#{FEATURE_ID}.unhost", :param => "space", :checked => false,
                               :label => "Remove the Space from its missing Zone"),
        "make_independent" => Repair.new(:action => "#{FEATURE_ID}.make_independent", :param => "reference",
                                         :checked => false, :label => "Make the copy independent"),
        "restore_position" => Repair.new(:action => "#{FEATURE_ID}.volumes.restore_position", :param => "volume",
                                         :checked => true, :label => "Restore the Volume's position")
      }.freeze

      module_function

      def install(feature)
        feature.export_contributor(SECTION, :section_version => 2, :preflight => PREFLIGHT,
                                            :requires => [ZONES_SECTION],
                                            :result => {
                                              "space_zone_totals" => [Export::Privacy.fields(%w[zone_id] + TOTALS)],
                                              "space_segment_totals" => [
                                                Export::Privacy.fields(%w[building_segment] + TOTALS)
                                              ],
                                              "space_schedule" => [Export::Privacy.fields(SCHEDULE)]
                                            }, :report => method(:report),
                                            :projection => method(:zone_totals)) { |reader| records(reader) }
        feature.query(PREFLIGHT, :description => "Spaces export checks: every finding with where it is and its repair.",
                                 :refuses => [], :params => Shapes::NONE, :result => Export::PREFLIGHT_RESULT,
                                 :examples => [{}]) { |request| preflight(request) }
      end

      # The Spaces schedule: per Zone, the table's columns and the Zone's totals, then the totals per
      # Building-Segment, and one line naming any Space drawn off to the side of its Zone. A Space in a By
      # Program Zone shows "By Program" in its airflow columns.
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
        return "By Program" if value.nil? && quantity == "airflow"
        return "" if value.nil?

        format("%.2f", PhComposer::Units.to_display(value, :quantity => quantity, :system => display_units))
      end

      # A total row: the reported area and volume totals, and the airflows summed over its Spaces, a dash while
      # any of them is in a By Program Zone.
      def total_row(label, totals, spaces, display_units)
        by_program = spaces.any? { |row| AIRFLOWS.all? { |key| row[key].nil? } }
        COLUMNS.map do |_heading, field, quantity|
          next label if field == "number"
          next cell(totals, field, quantity, display_units) if TOTALS.include?(field) && totals.key?(field)
          next "" unless AIRFLOWS.include?(field) && !spaces.empty?
          next "\u2014" if by_program

          cell({ field => spaces.sum { |row| row[field].to_f } }, field, quantity, display_units)
        end
      end

      def preflight(request)
        read = request.query("#{FEATURE_ID}.all")
        findings = []
        repairs = []
        # A Space in a Zone export leaves out goes with it, and nothing about it is checked.
        zones = Zones::ExportProjection.left_out_zones(request.model)
        left_out = zones.to_h { |zone| [zone.record.fetch("id"), zone.record.fetch("name")] }
        owners = read.fetch("spaces").to_h { |space| [space, left_out_owner(space, zones)] }
        spaces, gone = read.fetch("spaces").partition { |space| owners.fetch(space).nil? }
        rows = spaces.flat_map do |space|
          [space] + space.fetch("volumes").flat_map { |volume| [volume] + volume.fetch("floor_segments") }
        end
        # A Space, Volume or Floor Segment row, or a stray record, carries its reference: it is located, and
        # offers the repair its finding names.
        strays = read.fetch("findings").reject do |finding|
          path = Array(finding.dig("reference", "entity_path"))
          zones.any? { |zone| path.length > zone.path.length && path[0, zone.path.length] == zone.path }
        end
        located = rows.flat_map { |row| Array(row["findings"]).map { |finding| [finding, row.fetch("reference")] } } +
                  strays.map { |finding| [finding, finding.fetch("reference")] }
        located.each do |finding, reference|
          findings << finding_row(finding, reference, reference_id(reference))
          repair = repair_row(finding, reference)
          repairs << repair if repair
        end
        findings.concat(offset_findings(request.model, left_out))
        findings.concat(metadata_findings(request))
        findings.concat(left_out_findings(gone.map { |space| owners.fetch(space) }, left_out))
        findings.concat(without_spaces_findings(read.fetch("zones"), left_out))
        { "findings" => findings, "repairs" => repairs.uniq { |row| row.fetch("id") } }
      rescue CodedError => error
        { "findings" => [{ "code" => error.code, "section" => SECTION, "object_id" => nil,
                           "message" => error.message, "blocks_export" => true }], "repairs" => [] }
      end

      # One warning per exported Zone no Space names, from the Spaces read's Zone rows: a copied Zone's rows are
      # read together by id, as its Spaces' membership is. Not blocking: WUFI-Passive and METr open such a Zone
      # with no iCFA, net volume or ventilation.
      def without_spaces_findings(zone_rows, left_out)
        zone_rows.group_by { |zone| zone.fetch("zone_id") }.filter_map do |zone_id, rows|
          next if left_out.key?(zone_id) || rows.sum { |zone| zone.fetch("space_count") }.positive?

          { "code" => "space.zone_without_spaces", "section" => SECTION, "object_id" => zone_id,
            "message" => without_spaces_message(rows.first["name"]), "blocks_export" => false }
        end
      end

      def without_spaces_message(zone_name)
        "Zone #{zone_name} has no Spaces. It exports its geometry, but WUFI-Passive and METr give it no iCFA, net " \
          "volume or ventilation. Add Spaces before calculating."
      end

      # The metadata extraction refuses, read as `records` reads each Space, Volume, Space Floor and Floor
      # Segment: user_data passed through, and the envelopes another contributor claims on each kind. Nothing
      # inside a Zone in no Building Segment is read: it never leaves.
      def metadata_findings(request)
        check = Export::MetadataCheck
        skip = Zones::ExportProjection.left_out_zones(request.model).map(&:entity)
        floors = check.entity_records(request.model, VOLUME_STORE, :skip => skip).map { |volume| floor_part(volume) }
        { SPACE_STORE => SPACE_KIND, VOLUME_STORE => VOLUME_KIND, FLOOR_SEGMENT_STORE => FLOOR_SEGMENT_KIND }
          .flat_map do |store, kind|
            check.findings(request, check.entity_records(request.model, store, :skip => skip),
                           :section => SECTION, :user_data => true, :target_kind => kind)
          end + check.findings(request, floors, :section => SECTION, :user_data => true)
      end

      # The id of the Zone in no Building Segment that a Spaces row names or sits inside, or nil.
      def left_out_owner(space, zones)
        path = Array(space.dig("reference", "entity_path"))
        zones.find do |zone|
          zone.record.fetch("id") == space.dig("zone", "zone_id") ||
            (path.length > zone.path.length && path[0, zone.path.length] == zone.path)
        end&.record&.fetch("id")
      end

      # One row per left-out Zone counting the Spaces that go with it, from the Zone id of each.
      def left_out_findings(zone_ids, left_out)
        zone_ids.tally.sort.map do |zone_id, count|
          { "code" => "space.zone_left_out", "section" => SECTION, "object_id" => zone_id,
            "message" => left_out_message(left_out.fetch(zone_id), count), "blocks_export" => false }
        end
      end

      def left_out_message(zone_name, count)
        "#{count} #{count == 1 ? 'Space' : 'Spaces'} in Zone #{zone_name}, which is in no Building Segment, " \
          "#{count == 1 ? 'is' : 'are'} left out of export with it."
      end

      def finding_row(finding, reference, object_id)
        row = { "code" => finding.fetch("code"), "section" => SECTION, "object_id" => object_id,
                "message" => finding.fetch("message"), "blocks_export" => finding.fetch("blocks_export") }
        reference ? row.merge("locate" => { "name" => "#{FEATURE_ID}.locate",
                                            "params" => { "reference" => reference } }) : row
      end

      # A Space drawn off to the side of its Zone exports as drawn; the preflight says so, without blocking. A
      # Space in a Zone `left_out` names does not export at all.
      def offset_findings(model, left_out = {})
        zones = Zones::Occurrences.zones(model).reject { |zone| left_out.key?(zone.record.fetch("id")) }
        spaces = Occurrences.scan(model, :strict => false).spaces
        space_paths = spaces.map(&:path)
        spaces.filter_map do |space|
          zone = zones.select { |candidate| candidate.record.fetch("id") == space.record["zone_id"] }.min_by(&:path)
          next unless zone

          # The Zone's own Faces: none inside a Space, should one be put in a Zone Group natively.
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
        # What sits inside a Zone in no Building Segment leaves with it, before anything about it is checked.
        kept = lambda do |dictionary, kind|
          snapshot.records(dictionary, :kind => kind)
                  .reject { |entry, _record| Zones::ExportProjection.left_out?(reader, entry.path) }
        end
        note_left_out(reader)
        spaces = unique!(kept.call(SPACE_STORE.dictionary, "group"), "Space")
        volumes = unique!(kept.call(VOLUME_STORE.dictionary, "group"), "Volume")
        segments = unique!(kept.call(FLOOR_SEGMENT_STORE.dictionary, "face"), "Floor Segment")
        structure!(spaces, volumes, segments)
        # Each Volume and Floor Segment filed under the path of the container it sits directly in, and each
        # Zone's own-Face extents, once per export: per Space, a lookup and not a pass over the snapshot.
        volumes_in = volumes.group_by { |volume, _| volume.path[0...-1] }
        segments_in = segments.group_by { |segment, _| segment.path[0...-1] }
        space_paths = spaces.to_h { |space, _| [space.path, true] }
        zone_bounds = {}
        # Every Space record, left out or not, as the reads take the mode, so the table and the export agree.
        modes = Metrics.zone_modes(snapshot.records(SPACE_STORE.dictionary, :kind => "group").map(&:last))
        left_out = Hash.new { |hash, key| hash[key] = [] }
        rows = spaces.filter_map do |entry, record|
          zone = hosting_zone(reader, record)
          # A Space in a Zone in no Building Segment leaves with its Zone: not at all.
          unless Zones::Schema.exported?(zone.last)
            left_out[zone.last] << record
            next
          end

          Spaces.validate!(SPACE, record)
          own = volumes_in.fetch(entry.path, [])
          exported = reader.entity_record(record, :fields => %w[name number] + AIRFLOWS, :target_kind => SPACE_KIND,
                                                  :path => entry.path, :user_data => true)
          bounds = zone_bounds.fetch(zone.first.path) do
            zone_bounds[zone.first.path] = Extents.bounds(own_face_points(reader, zone.first, space_paths))
          end
          exported.merge("zone_id" => zone.last.fetch("id"), "airflow_mode" => modes.fetch(record["zone_id"]),
                         "offset_from_zone" => Extents.outside_bounds?(floor_points(own, segments_in), bounds),
                         "volumes" => own.map { |volume| volume_record(reader, volume, segments_in) }
                                         .sort_by { |row| row.fetch("id") })
        end
        left_out.each do |zone, records|
          reader.note("space.zone_left_out", zone.fetch("id"), left_out_message(zone.fetch("name"), records.length))
        end
        rows.sort_by { |row| row.fetch("id") }
      end

      # The section's registered projection, for a contributor that needs each exported Zone's Space totals
      # (`reader.section(SECTION)`): one row per Zone that holds a Volume, in Zone id order, with the sums of its
      # Volumes' floor area, weighted floor area (iCFA) and net volume as the metrics measure them (net volume is
      # net floor area times average clear ceiling height), which is what honeybee-ph and PHX read back. What sits
      # in a Zone in no Building Segment is left out with it, and a Volume with no height counts no volume here:
      # the section's records refuse it.
      def zone_totals(reader)
        snapshot = reader.snapshot
        kept = lambda do |dictionary, kind|
          snapshot.records(dictionary, :kind => kind)
                  .reject { |entry, _record| Zones::ExportProjection.left_out?(reader, entry.path) }
        end
        spaces = kept.call(SPACE_STORE.dictionary, "group").to_h { |entry, record| [entry.path, record] }
        segments_in = kept.call(FLOOR_SEGMENT_STORE.dictionary, "face").group_by { |entry, _| entry.path[0...-1] }
        totals = Hash.new { |hash, key| hash[key] = TOTALS.to_h { |total| [total, 0.0] } }
        kept.call(VOLUME_STORE.dictionary, "group").each do |entry, record|
          zone_id = spaces[entry.path[0...-1]]&.fetch("zone_id", nil)
          next unless zone_id

          metrics = segments_in.fetch(entry.path, []).map do |segment, segment_record|
            Metrics.segment(segment.geometry.loops_m, segment.geometry.normal, segment_record)
          end
          volume = Metrics.volume(record, metrics)
          TOTALS.each { |total| totals[zone_id][total] += volume.fetch(total) || 0.0 }
        end
        totals.sort.map { |zone_id, sums| { "zone_id" => zone_id }.merge(sums) }
      end

      # One note per Zone in no Building Segment counting the Spaces inside it that leave with it.
      def note_left_out(reader)
        gone = reader.snapshot.records(SPACE_STORE.dictionary, :kind => "group").filter_map do |entry, _record|
          next unless Zones::ExportProjection.left_out?(reader, entry.path)

          Zones::ExportProjection.enclosing_zones(reader, entry.path).first&.last
        end
        gone.group_by { |zone| zone.fetch("id") }.sort.each do |zone_id, rows|
          reader.note("space.zone_left_out", zone_id, left_out_message(rows.first.fetch("name"), rows.length))
        end
      end

      # The outer-loop points of the Floor Segments in these Volumes.
      def floor_points(volumes, segments_in)
        volumes.flat_map do |volume, _|
          segments_in.fetch(volume.path, []).flat_map { |segment, _| segment.geometry.loops_m.first }
        end
      end

      # The snapshot Zone the record names. Blocked when it names none, or one that is gone.
      def hosting_zone(reader, record)
        zone_id = record["zone_id"]
        raise Export::Blocked.new("space.outside_zone", "Space #{record.fetch('id')} is in no Zone.") unless zone_id

        found = Zones::ExportProjection.zone_entry(reader, zone_id)
        return found if found

        raise Export::Blocked.new("space.zone_missing",
                                  "Space #{record.fetch('id')} names a Zone that is no longer in the Model.")
      end

      # The outer-loop points of the Zone's own Faces, those inside no Space: the extents the preflight's offset
      # rule measures a Space's Floor Segments against, from the snapshot.
      def own_face_points(reader, zone_entry, space_paths)
        own = Zones::ExportProjection.zone_faces(reader, zone_entry).reject do |face|
          (1...face.path.length).any? { |length| space_paths.key?(face.path[0, length]) }
        end
        own.flat_map { |face| face.geometry.loops_m.first }
      end

      def volume_record(reader, (entry, record), segments_in)
        Spaces.validate!(VOLUME, record)
        height = record["avg_ceiling_height_m"]
        unless height
          raise Export::Blocked.new("space.height_missing", "Volume #{record.fetch('id')} has no average clear " \
                                                            "ceiling height.")
        end

        # An empty Volume is a warning, not a block: it leaves with no Floor Segment and no prism.
        own = segments_in.fetch(entry.path, [])
        rows = own.map { |segment| segment_record(reader, segment) }.sort_by { |row| row.fetch("id") }
        prisms = Prism.call(own.map { |segment, _| segment.geometry.loops_m }, height)
        floor = reader.entity_record(floor_part(record), :fields => [], :user_data => true)
        reader.entity_record(record, :fields => %w[display_name avg_ceiling_height_m floor_id],
                                     :target_kind => VOLUME_KIND, :path => entry.path, :user_data => true)
              .merge(floor.key?("user_data") ? { "floor_user_data" => floor.fetch("user_data") } : {})
              .merge("floor_segments" => rows, "geometry" => prisms.flat_map(&:polygons))
      end

      # A Volume's Space Floor as the part its map belongs to: it leaves on the honeybee-ph SpaceFloor, never on
      # the Volume, under the same reserved-key rule.
      def floor_part(volume)
        { "id" => volume["floor_id"], "user_data" => volume.fetch("floor_user_data", {}) }
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

      # A Volume sits directly in a Space, a Floor Segment directly in a Volume, and no Space inside another.
      def structure!(spaces, volumes, segments)
        space_paths = spaces.to_h { |entry, _| [entry.path, true] }
        nested = space_paths.keys.any? do |inner|
          (1...inner.length).any? { |length| space_paths.key?(inner[0, length]) }
        end
        raise Export::Blocked.new("space.nested", "A Space is inside another Space.") if nested

        unless volumes.all? { |entry, _| space_paths.key?(entry.path[0...-1]) }
          raise Export::Blocked.new("space.volume_nested", "A Volume is not directly inside a Space.")
        end

        volume_paths = volumes.to_h { |entry, _| [entry.path, true] }
        return if segments.all? { |entry, _| volume_paths.key?(entry.path[0...-1]) }

        raise Export::Blocked.new("space.segment_misplaced", "A Floor Segment is not directly inside a Volume.")
      end
    end
  end
end
