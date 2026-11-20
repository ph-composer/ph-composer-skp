# frozen_string_literal: true

module PhComposer
  module Shading
    # The Shades export section (context/CONTRACTS.md, "Translation sections and artifacts"): one record per
    # Shading Face occurrence, read from the export snapshot and never the live Model, for the Python section that
    # adds each as an orphaned honeybee `Shade` (python/ph_composer_translation/shade_sections.py). Which Faces are
    # shading and what they are called is Reads' rule, the one `shading.list` and Colour-by apply live, over
    # Reads::Container rows built from the snapshot entries above each Face; the Zones section's projection names
    # the Zone containers, and inside a Zone Zones' own detached envelope test decides, so a Face is a Room's or a
    # Shade, never both.
    #
    # The section is optional and never blocks for its own reasons: a Face that cannot become a Shade is left out
    # with a note. The mark's `user_data` stays in the Model with an `export.metadata_omitted` note, and its
    # `extension_data` follows the foundation's left-out rules, as every entity record's does.
    module ExportSection
      SECTION = Preflight::SECTION
      PREFLIGHT = "#{FEATURE_ID}.export_preflight"
      ZONES = "ph_composer.zones.export.zones"
      COMPONENT_FIELDS = %w[display_name face_count area_m2].freeze
      RESULT = { "shading_components" => [PhComposer::Export::Privacy.fields(COMPONENT_FIELDS)],
                 "shade_count" => nil, "area_m2" => nil }.freeze
      # Below this world area (1 mm2) a Face is degenerate and is left out.
      MINIMUM_AREA_M2 = 1.0e-6
      CONTAINER_KINDS = %w[group component_instance].freeze
      METADATA_KEYS = %w[user_data extension_data].freeze

      module_function

      def install(feature)
        feature.export_contributor(SECTION, :section_version => 1, :preflight => PREFLIGHT, :requires => [ZONES],
                                            :result => RESULT, :report => method(:report)) { |reader| records(reader) }
      end

      # One record per Shading Face occurrence, in id order, each `{id, display_name, boundary, holes}` in world
      # metres, outer loop first as the snapshot captured it.
      def records(reader)
        snapshot = reader.snapshot
        zones = reader.section(ZONES).to_h { |row| [row.fetch("zone_path"), row.fetch("name")] }
        marks(reader, snapshot)
        shading_entries(reader, zones).group_by { |entry, _name| identifier(entry.path) }.filter_map do |id, rows|
          entry, name = rows.first
          problem = if rows.length > 1
                      ["target.ambiguous", ambiguous(entry.path)]
                    else
                      geometry_problem(entry.path, entry.geometry)
                    end
          if problem
            reader.note(problem.first, id, problem.last)
            next
          end

          geometry = entry.geometry
          { "id" => id, "display_name" => name, "boundary" => geometry.outer_loop, "holes" => geometry.holes }
        end.sort_by { |record| record.fetch("id") }
      end

      # The Shade identifier of the Face occurrence at a root path, and the id a mark at that path is reported
      # under: `shd_` and a digest of the path, so each placement is its own Shade and a re-export gives the same.
      def identifier(path)
        Records::Identity.derived("shd", path)
      end

      # Every Shading Face entry in the snapshot with the component name it exports under, as [entry, name].
      # Each container's row is built once per path.
      def shading_entries(reader, zones)
        snapshot = reader.snapshot
        containers = snapshot.entries.select { |entry| CONTAINER_KINDS.include?(entry.kind) }
                             .group_by(&:path).transform_values(&:first)
        rows = {}
        snapshot.entries.filter_map do |entry|
          next unless entry.kind == "face"

          above = (1...entry.path.length).map do |length|
            path = entry.path[0, length]
            rows[path] ||= container(containers.fetch(path), zones)
          end
          next unless exported?(reader, entry, above)

          [entry, Reads.component_name(above)]
        end
      end

      # Reads.exported? over the snapshot. Inside a Zone the classification clause is Zones' own detached test
      # (`outside_envelope?`), so a Face the Room keeps is never a Shade and one it leaves out always is.
      def exported?(reader, entry, above)
        return false unless Reads.shading_face?(:marked => Mark::STORE.carried_by?(entry.dictionaries),
                                                :owned => Records::EntityStore.claimed_entries?([entry]),
                                                :containers => above)

        above.none?(&:zone?) || Zones::ExportProjection.outside_envelope?(reader, entry)
      end

      # The Reads::Container row for one Group or component entry: a Group's own name; an instance's own name,
      # else its definition's, as Targets reads them live.
      def container(entry, zones)
        own = entry.native_name.to_s
        name = own.strip.empty? && entry.native ? entry.native.fetch("definition_name", "") : own
        Reads::Container.new(:path => entry.path, :marked => Mark::STORE.carried_by?(entry.dictionaries),
                             :owned => Records::EntityStore.claimed_entries?([entry]),
                             :zone_name => zones[entry.path], :name => name)
      end

      # Each mark through the metadata boundary, once per occurrence: its user_data stays in the Model with a note,
      # and its extension_data follows the left-out rules. A mark whose text is not a JSON object still marks its
      # entity (Mark reads by presence); it is noted and has no metadata to read.
      def marks(reader, snapshot)
        snapshot.entries.each do |entry|
          next unless Mark::STORE.carried_by?(entry.dictionaries)

          id = identifier(entry.path)
          record = parse(entry.dictionaries.dig(Mark::STORE.dictionary, Mark::STORE.key))
          if record
            reader.entity_record(record.merge("id" => id), :fields => [])
          else
            reader.note("record.unreadable", id, unreadable(entry.path))
          end
        end
      end

      # The mark's record when it is a JSON object whose metadata maps are objects or null (read as absent); else
      # nil.
      def parse(text)
        record = text.is_a?(String) ? JSON.parse(text) : nil
        return nil unless record.is_a?(Hash)

        record = record.reject { |key, value| METADATA_KEYS.include?(key) && value.nil? }
        METADATA_KEYS.all? { |key| record.fetch(key, {}).is_a?(Hash) } ? record : nil
      rescue JSON::ParserError
        nil
      end

      # Why the Face occurrence at `path`, with its FaceGeometry::Snapshot, cannot become a Shade, as
      # [code, message], or nil.
      def geometry_problem(path, geometry)
        return nil if geometry.loops_m.all? { |loop| loop.length >= 3 } && geometry.area_m2 >= MINIMUM_AREA_M2

        ["shading.geometry_invalid", "The Shading Face at path #{path.inspect} has no area or too few " \
                                     "points to become a Shade; it was left out."]
      end

      def ambiguous(path)
        "More than one Face has the path #{path.inspect}, so neither can be told apart as a Shade; they were left " \
          "out."
      end

      def unreadable(path)
        "The shading mark at path #{path.inspect} cannot be read. It still marks its entity; clear and set it " \
          "again to repair it."
      end

      # The Shading section: each shading component's name, Face count and area, and the totals; absent when the
      # export wrote no Shade.
      def report(result, display_units)
        rows = result.fetch("shading_components", [])
        return [] if rows.empty?

        unit = PhComposer::Units.label(:quantity => "area", :system => display_units)
        table = rows.map do |row|
          [row.fetch("display_name"), row.fetch("face_count"), area(row.fetch("area_m2"), display_units)]
        end
        total = "#{result.fetch('shade_count')} Shades in #{rows.length} shading components, " \
                "#{area(result.fetch('area_m2'), display_units)} #{unit} in all."
        html = PhComposer::Export::ReportHtml.table(["Shading component", "Faces", "Area (#{unit})"], table) +
               PhComposer::Export::ReportHtml.paragraph(total)
        [PhComposer::Export::ReportHtml.section("Shading", html)]
      end

      def area(value, display_units)
        format("%.2f", PhComposer::Units.to_display(value, :quantity => "area", :system => display_units))
      end
    end
  end
end
