# frozen_string_literal: true

module PhComposer
  module Spaces
    # The Spaces readouts, through the shared service (context/EXTENSIBILITY.md, "Colour-by readouts"), shown
    # with any mode or none and writing nothing.
    #
    # - Show Spaces, on by default in every Model session: each Volume's prism outline, and one line per Space
    #   at its reference point, the centroid of its largest Floor Segment projected to that segment's mean
    #   height: number and name, then weighted area, net volume and supply and extract when those options are
    #   on. A Space with no Floor Segment has no label and a Volume with no height no outline. The text is
    #   drawn at that point's screen position and is not depth-tested.
    # - Selection totals: with Spaces, Volumes or Floor Segments selected, HUD lines summing weighted area,
    #   net volume, supply and extract over the Spaces they belong to, each Space once.
    #
    # The label options are this Model session's, set by a view command or the native Space labels menu.
    module Readouts
      SHOW = "#{FEATURE_ID}.show"
      SELECTION_TOTALS = "#{FEATURE_ID}.selection_totals"
      OPTIONS = {
        "weighted_area" => "Weighted area (iCFA)", "net_volume" => "Net volume", "airflows" => "Supply and extract"
      }.freeze
      MENU = "Space labels"

      # What one Space contributes: its record, its summed metrics, its label point in world metres, and its
      # Volumes' views.
      SpaceTotals = Struct.new(:space, :weighted_area_m2, :net_volume_m3, :point_m, :volumes, keyword_init: true)

      module_function

      def install(feature)
        feature.colour_readout(SHOW, :label => "Show Spaces", :on_by_default => true) { |read| show(read) }
        feature.colour_readout(SELECTION_TOTALS, :label => "Spaces selection totals", :selection => true) do |read|
          selection_totals(read)
        end
        install_options(feature)
      end

      def install_options(feature)
        result = Shapes.object(OPTIONS.to_h do |key, label|
          [key, { "type" => "boolean", "description" => "Whether the labels show #{label.downcase}." }]
        end)
        feature.query("#{FEATURE_ID}.labels.options",
                      :description => "Which optional lines the Space labels show, for this Model session.",
                      :refuses => [], :params => Shapes::NONE, :result => result, :examples => [{}]) do |request|
          options(request.session).dup
        end
        feature.snapshot_section("#{FEATURE_ID}.label_options", :query => "#{FEATURE_ID}.labels.options")
        feature.view_command("#{FEATURE_ID}.labels.set_options",
                             :description => "Show or hide the Space labels' optional lines for this Model session.",
                             :refuses => [], :params => Shapes.object(result.fetch("properties"),
                                                                      :optional => OPTIONS.keys),
                             :result => result, :examples => [{ "weighted_area" => true }]) do |request|
          set_options(request.session, request.params)
        end
        OPTIONS.each do |key, label|
          # Offered while the labels are on, the only time a line choice shows anything; the viewport menu
          # offers them over a selection, not on every right-click.
          feature.menu_item("#{FEATURE_ID}.labels_#{key}_menu", :label => label, :menu => MENU,
                                                                :available => lambda { |read|
                                                                  space_selected?(read.model) &&
                                                                    ColourBy.for(read.session).readouts_on
                                                                            .include?(SHOW)
                                                                },
                                                                :state => lambda { |session|
                                                                  options(session)[key] ? MF_CHECKED : MF_UNCHECKED
                                                                }) do |session|
            set_options(session, key => !options(session)[key])
          end
        end
      end

      # Whether the selection holds a Space, a Volume or a Floor Segment, the things the labels are for.
      def space_selected?(model)
        model.selection.to_a.any? do |entity|
          [SPACE_STORE, VOLUME_STORE, FLOOR_SEGMENT_STORE].any? { |store| store.marks?(entity) }
        end
      end

      def options(session)
        session.feature_state(:spaces_label_options) { OPTIONS.keys.to_h { |key| [key, false] } }
      end

      # Merges the given options and redraws the labels, which the revision alone would not rebuild.
      def set_options(session, values)
        options(session).merge!(values.slice(*OPTIONS.keys).transform_values { |value| value == true })
        session.changed(:spaces, :label_options)
        ColourBy.for(session).invalidate!(:force => true)
        options(session).dup
      end

      def show(read)
        chosen = options(read.session)
        rows = totals(read)
        anchors = rows.filter_map do |row|
          next unless row.point_m

          ColourBy::Anchor.new(:point => point(row.point_m), :path => row.space.path,
                               :parts => label_parts(row, chosen))
        end
        ColourBy::Readout.new(:anchors => anchors, :hud => [], :outlines => rows.flat_map { |row| outlines(row) })
      end

      # One outline per Volume, so hiding a Volume hides its own lines.
      def outlines(row)
        row.volumes.map do |view|
          pairs = Prism.outline(view.segments.flat_map(&:prism))
          ColourBy::Outline.new(:path => view.volume.path, :points => pairs.flatten(1).map { |corner| point(corner) })
        end
      end

      def label_parts(row, chosen)
        record = row.space.record
        parts = [[record.fetch("number"), record.fetch("name")].map(&:to_s).reject(&:empty?).join(" ")]
        parts.push("  ", ["area", row.weighted_area_m2]) if chosen["weighted_area"]
        parts.push("  ", ["volume", row.net_volume_m3]) if chosen["net_volume"]
        if chosen["airflows"] && (flows = Metrics.airflows(record)).values.none?(&:nil?)
          parts.push("  ", ["airflow", flows.fetch("v_sup_m3h")], " / ", ["airflow", flows.fetch("v_eta_m3h")])
        end
        parts
      end

      def selection_totals(read)
        selected = Array(read.selection)
        rows = totals(read).select do |row|
          path = row.space.path
          # The Space itself, or anything inside it: a Volume, a Floor Segment, a Face.
          selected.any? { |chosen| chosen[0, path.length] == path }
        end
        ColourBy::Readout.new(:anchors => [], :hud => rows.empty? ? [] : hud(rows))
      end

      # Airflows follow the any-set rule, as a Zone's sums do: while any selected Space inherits its Zone's
      # airflow, the sums would read as complete when they are not, so the line says how many inherit instead.
      def hud(rows)
        inheriting = rows.count { |row| Metrics.airflow_mode(row.space.record) == "inheriting" }
        flows = rows.map { |row| Metrics.airflows(row.space.record) }
        airflow = if inheriting.positive?
                    ["Supply and extract: #{inheriting} of #{rows.length} inherit the Zone's airflow"]
                  else
                    supply, extract = %w[v_sup_m3h v_eta_m3h].map { |key| flows.sum { |rates| rates.fetch(key) } }
                    ["Supply ", ["airflow", supply], "  Extract ", ["airflow", extract]]
                  end
        [["#{rows.length} #{rows.length == 1 ? 'Space' : 'Spaces'} selected"],
         ["Weighted area ", ["area", rows.sum(&:weighted_area_m2)]],
         ["Net volume ", ["volume", rows.sum(&:net_volume_m3)]], airflow]
      end

      # Every Space occurrence, summed from the same Volume views the modes draw from; a Space with no Volume
      # counts with no area, no volume and no label point.
      def totals(read)
        views = ColourModes.volume_views(read.model).group_by { |view| view.space.path }
        Occurrences.scan(read.model).spaces.map do |space|
          own = views.fetch(space.path, [])
          largest = own.flat_map(&:segments).max_by { |segment| segment.metrics.fetch("floor_area_m2") }
          SpaceTotals.new(:space => space,
                          :weighted_area_m2 => own.sum { |view| view.metrics.fetch("weighted_area_m2") },
                          :net_volume_m3 => own.sum { |view| view.metrics.fetch("net_volume_m3") || 0.0 },
                          :point_m => largest && centroid(largest), :volumes => own)
        end
      end

      # The plan centroid of a segment, its holes taken out, at its outer loop's mean height, in world metres.
      # Moments are taken about the outer loop's first point, so a segment far from the origin keeps its
      # precision.
      def centroid(segment)
        outer, *holes = FaceCapture.call(segment.occurrence.entity, segment.occurrence.transform).loops_m
        origin = outer.first
        z = outer.sum { |point| point[2] } / outer.length
        area, x_moment, y_moment = holes.map { |hole| moments(hole, origin) }
                                        .reduce(moments(outer, origin)) do |(a, mx, my), (ha, hx, hy)|
          [a - ha, mx - hx, my - hy]
        end
        return [origin[0], origin[1], z] unless area.positive?

        [origin[0] + (x_moment / area), origin[1] + (y_moment / area), z]
      end

      # A loop's plan area and first moments about `origin`, whatever its winding.
      def moments(loop, origin)
        local = loop.map { |x, y, _z| [x - origin[0], y - origin[1]] }
        twice = x_sum = y_sum = 0.0
        local.each_with_index do |(x, y), index|
          next_x, next_y = local[(index + 1) % local.length]
          cross = (x * next_y) - (next_x * y)
          twice += cross
          x_sum += (x + next_x) * cross
          y_sum += (y + next_y) * cross
        end
        sign = twice.negative? ? -1.0 : 1.0
        [sign * twice / 2.0, sign * x_sum / 6.0, sign * y_sum / 6.0]
      end

      def point(point_m)
        Geom::Point3d.new(*point_m.map { |value| value * ColourModes::INCHES_PER_M })
      end
    end
  end
end
