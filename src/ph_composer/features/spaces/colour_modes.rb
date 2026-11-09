# frozen_string_literal: true

module PhComposer
  module Spaces
    # The Spaces view's Colour-by modes, through the shared service (context/EXTENSIBILITY.md, "Colour-by
    # modes" and "Colour-by derived geometry"). Each draws the Volume preview prism (Prism) as its derived
    # geometry, so the prisms show while one of these modes is on and never otherwise.
    #
    # - By Space: each Volume by its Space's id, every Space a distinct hue on the categorical ramp, usually
    #   kept as others come and go (Palette.spread); the legend sums weighted area (iCFA).
    # - By ventilation: each Volume by what its Space supplies or extracts under the any-set rule; the legend
    #   sums the rates the category is named for, supply and extract both for a Space with both, once per Space.
    # - By weighting factor: each Floor Segment by its factor, with its own prism, since one Volume may hold
    #   several factors. A band's key is the factor's shortest exact text ("1", "0.5", "0.1234561"); the
    #   Spaces read publishes it on each Floor Segment row (`weighting_band`), so the panel's filter uses the
    #   same string and no two factors share a band. The legend sums floor area.
    # - By height: each Volume by its average clear ceiling height to the nearest 0.1 m; the legend sums net
    #   volume.
    #
    # A Volume with a finding that blocks export (no height, nested, a copied identity, its Space outside a Zone)
    # is incomplete in every mode, and still counted; the Spaces read decides, so the table and the modes agree.
    # A Volume with no Floor Segment is one incomplete entry in By weighting factor too.
    module ColourModes
      BY_WEIGHTING_FACTOR = "#{FEATURE_ID}.by_weighting_factor"
      BY_SPACE = "#{FEATURE_ID}.by_space"
      BY_VENTILATION = "#{FEATURE_ID}.by_ventilation"
      BY_HEIGHT = "#{FEATURE_ID}.by_height"
      # The Supply, Extract and Transfer columns offer By ventilation together.
      VENTILATION_GROUP = "ventilation"
      # Per category: its legend label, its colour, and the rates its legend row sums.
      VENTILATION = {
        "both" => ["Supply and extract", [44, 160, 44], %w[v_sup_m3h v_eta_m3h]],
        "supply" => ["Supply only", [31, 119, 180], %w[v_sup_m3h]],
        "extract" => ["Extract only", [214, 39, 40], %w[v_eta_m3h]],
        "transfer" => ["Transfer only", [148, 103, 189], %w[v_tran_m3h]],
        "none" => ["No airflow", [190, 190, 190], []],
        # Every rate unset: the Space uses its Zone's ventilation load, as the Spaces view's "Zone" says.
        "zone" => ["Zone ventilation", [196, 176, 150], []]
      }.freeze
      VENTILATION_COLOURS = VENTILATION.transform_values { |row| row[1] }.freeze
      INCHES_PER_M = 1.0 / 0.0254

      VolumeView = Struct.new(:space, :volume, :segments, :metrics, :height, :incomplete, keyword_init: true)
      SegmentView = Struct.new(:occurrence, :metrics, :prism, keyword_init: true)

      module_function

      def install(feature)
        feature.colour_mode(BY_SPACE, :label => "Space", :entity_kind => "volume",
                                      :colours => ColourBy::Palette.ramp) { |read| by_space(views(read)) }
        feature.colour_mode(BY_VENTILATION, :label => "Ventilation", :entity_kind => "volume",
                                            :group => VENTILATION_GROUP,
                                            :colours => ColourBy::Palette.fixed(VENTILATION_COLOURS)) do |read|
          by_ventilation(views(read))
        end
        feature.colour_mode(BY_WEIGHTING_FACTOR, :label => "Weighting factor", :entity_kind => "volume",
                                                 :colours => ColourBy::Palette.ramp) do |read|
          ColourBy::Palette.spread_entries(by_weighting_factor(views(read)))
        end
        feature.colour_mode(BY_HEIGHT, :label => "Height", :entity_kind => "volume",
                                       :colours => ColourBy::Palette.ramp, :sort => method(:height_order)) do |read|
          ColourBy::Palette.spread_entries(by_height(views(read)))
        end
      end

      def band(factor)
        text = Float(factor).to_s
        text.end_with?(".0") ? text.delete_suffix(".0") : text
      end

      # Every Volume in a Space, with its Floor Segments' captured metrics and prisms, read once per rebuild.
      # `read` is the projection's read request; the Spaces read says which Volumes are blocked.
      def views(read)
        volume_views(read.model, blocked_paths(read))
      end

      # `blocked` is the Volume paths to mark incomplete. A caller that draws no incomplete state leaves it
      # out and is spared the whole Spaces read.
      def volume_views(model, blocked = {})
        Occurrences.scan(model).spaces.flat_map do |space|
          space.volumes.map do |volume|
            height = volume.record["avg_ceiling_height_m"]
            segments = volume.segments.map do |segment|
              geometry = FaceCapture.call(segment.entity, segment.transform)
              SegmentView.new(:occurrence => segment,
                              :metrics => Metrics.segment(geometry.loops_m, geometry.normal, segment.record),
                              :prism => Prism.call([geometry.loops_m], height))
            end
            VolumeView.new(:space => space, :volume => volume, :segments => segments, :height => height,
                           :metrics => Metrics.volume(volume.record, segments.map(&:metrics)),
                           :incomplete => blocked.include?(volume.path))
          end
        end
      end

      # The Volumes the Spaces read gives a finding that blocks export: on the Volume, one of its Floor
      # Segments or its Space, or a stray record inside it, such as a Floor Segment below a Group within it,
      # which the read reports among its top-level findings.
      def blocked_paths(read)
        value = read.query("#{FEATURE_ID}.all")
        blocks = ->(row) { Array(row["findings"]).any? { |finding| finding["blocks_export"] } }
        found = {}
        volumes = value.fetch("spaces").flat_map do |space|
          space.fetch("volumes").map do |volume|
            path = volume.dig("reference", "entity_path")
            found[path] = true if blocks.call(space) || blocks.call(volume) ||
                                  volume.fetch("floor_segments").any?(&blocks)
            path
          end
        end
        value.fetch("findings").select { |finding| finding["blocks_export"] }.each do |finding|
          inside = finding.dig("reference", "entity_path")
          owner = volumes.select { |path| path.length < inside.length && inside[0, path.length] == path }
                         .max_by(&:length)
          found[owner] = true if owner
        end
        found
      end

      # Every Space a distinct hue up to the ramp's length (Palette.spread), as the entry's own colour.
      def by_space(views)
        colours = ColourBy::Palette.spread(views.map { |view| view.space.record.fetch("id") })
        views.map do |view|
          record = view.space.record
          label = [record.fetch("number"), record.fetch("name")].map(&:to_s).reject(&:empty?).join(" ")
          entry(view, record.fetch("id"), label, ["area", view.metrics.fetch("weighted_area_m2")],
                :colour => colours[record.fetch("id")])
        end
      end

      def by_ventilation(views)
        counted = {}
        views.map do |view|
          category = ventilation(view.space.record)
          label, _colour, rates = VENTILATION.fetch(category)
          # A Space occurrence's rates count once, on its first Volume; the other Volumes add zero. Occurrences are
          # told apart by path, so a copy still awaiting repair adds its own rates, as the read sums them.
          first = !counted.key?(view.space.path)
          counted[view.space.path] = true
          flows = Metrics.airflows(view.space.record)
          figure = rates.map { |rate| ["airflow", first ? flows.fetch(rate).to_f : 0.0] }
          entry(view, category, label, figure.empty? ? nil : figure)
        end
      end

      # The any-set rule's rates: supply, extract, both, transfer alone, or none set above zero; a Space with
      # no rate set at all inherits its Zone's airflow.
      def ventilation(record)
        return "zone" if Metrics.airflow_mode(record) == "inheriting"

        rates = Metrics.airflows(record)
        supply, extract, transfer = rates.values_at("v_sup_m3h", "v_eta_m3h", "v_tran_m3h").map(&:to_f)
        return "both" if supply.positive? && extract.positive?
        return "supply" if supply.positive?
        return "extract" if extract.positive?

        transfer.positive? ? "transfer" : "none"
      end

      def by_weighting_factor(views)
        views.flat_map do |view|
          next [entry(view, nil, "No Floor Segment", nil, :incomplete => true)] if view.segments.empty?

          view.segments.map do |segment|
            occurrence = segment.occurrence
            key = band(occurrence.record.fetch("weighting_factor"))
            ColourBy::Entry.new(:entity => occurrence.entity, :transform => occurrence.transform, :value => key,
                                :label => key, :path => occurrence.path,
                                :state => view.incomplete ? :incomplete : nil,
                                :figure => ["area", segment.metrics.fetch("floor_area_m2")],
                                :derived => derived(segment.prism))
          end
        end
      end

      def by_height(views)
        views.map do |view|
          next entry(view, nil, "No height", nil) unless view.height

          # Decimal rounding, half up: 2.55 m is the 2.6 band, as it reads.
          step = view.height.round(1)
          entry(view, format("%.1f", step), [["length", step]], ["volume", view.metrics.fetch("net_volume_m3")])
        end
      end

      # Lowest height first; a Volume with none last.
      def height_order(row)
        [row.value.nil? ? 1 : 0, row.value.to_f]
      end

      def entry(view, value, label, figure, incomplete: view.incomplete, colour: nil)
        volume = view.volume
        ColourBy::Entry.new(:entity => volume.entity, :transform => volume.transform, :path => volume.path,
                            :value => value, :label => label, :figure => figure, :colour => colour,
                            :state => incomplete ? :incomplete : nil,
                            :derived => derived(view.segments.flat_map(&:prism)))
      end

      # The prisms' polygons in world inches, as the service draws them.
      def derived(prisms)
        polygons = prisms.flat_map do |shape|
          shape.polygons.map do |polygon|
            polygon.map { |x, y, z| Geom::Point3d.new(x * INCHES_PER_M, y * INCHES_PER_M, z * INCHES_PER_M) }
          end
        end
        ColourBy::Derived.new(:polygons => polygons, :segments => [])
      end
    end
  end
end
