# frozen_string_literal: true

module PhComposer
  module Spaces
    # Pure: detached geometry and records in, SI quantities out. A Floor Segment's area is its world
    # outline projected onto the horizontal plane, so a sloped Face counts its plan area; metrics, the
    # volume preview and the export use this one projection.
    module Metrics
      # A Face whose normal is within about 0.08 degrees of vertical reads as horizontal.
      HORIZONTAL_Z = 0.999999
      # A Face whose normal is within about 0.6 degrees of horizontal is a wall: it has no plan area to count.
      VERTICAL_Z = 0.01
      # Supply and extract differ by more than this share of the larger sum.
      IMBALANCE_SHARE = 0.1
      # The quantities a Zone, a Building-Segment and the Model sum.
      TOTALS = %w[floor_area_m2 weighted_area_m2 net_volume_m3].freeze

      module_function

      # Plan area of the outer loop less its holes, in m2, from world loops in metres. Coordinates are
      # taken relative to the outer loop's first point, so a Face far from the origin loses no precision.
      def projected_area_m2(loops_m)
        outer, *holes = loops_m
        origin = outer.first
        [plan_area(outer, origin) - holes.sum { |hole| plan_area(hole, origin) }, 0.0].max
      end

      def plan_area(loop, origin)
        local = loop.map { |x, y, _z| [x - origin[0], y - origin[1]] }
        twice = local.each_with_index.sum do |(x, y), index|
          next_x, next_y = local[(index + 1) % local.length]
          (x * next_y) - (next_x * y)
        end
        twice.abs / 2.0
      end

      def horizontal?(normal)
        normal[2].abs >= HORIZONTAL_Z
      end

      def vertical?(normal)
        normal[2].abs < VERTICAL_Z
      end

      def segment(loops_m, normal, record)
        area = projected_area_m2(loops_m)
        { "floor_area_m2" => area, "weighted_area_m2" => area * record.fetch("weighting_factor"),
          "net_area_m2" => area * record.fetch("net_area_factor"), "horizontal" => horizontal?(normal) }
      end

      # Net volume is net floor area times the average clear ceiling height; nil until a height exists.
      def volume(record, segments)
        totals = sums(segments, %w[floor_area_m2 weighted_area_m2 net_area_m2])
        height = record["avg_ceiling_height_m"]
        totals.merge("net_volume_m3" => height && (totals.fetch("net_area_m2") * height))
      end

      # `volumes` pairs each Volume's metrics with its height, nil when it has none. The Space's height
      # is the floor-area-weighted average over the Volumes that have one, read only.
      def space(volumes)
        metrics = volumes.map(&:first)
        totals = sums(metrics, %w[floor_area_m2 weighted_area_m2 net_area_m2])
        totals.merge("net_volume_m3" => metrics.sum { |volume| volume.fetch("net_volume_m3") || 0.0 },
                     "average_height_m" => average_height(volumes.reject { |_metrics, height| height.nil? }))
      end

      def average_height(volumes)
        area = volumes.sum { |metrics, _height| metrics.fetch("floor_area_m2") }
        return nil unless area.positive?

        volumes.sum { |metrics, height| metrics.fetch("floor_area_m2") * height } / area
      end

      # The any-set rule: a Space with any airflow set is user-specified and its unset rates are zero;
      # with all three unset it inherits the Zone's ventilation load.
      def airflow_mode(record)
        AIRFLOWS.any? { |key| record.key?(key) } ? "user_specified" : "inheriting"
      end

      # The rates the Space contributes: each set value, 0 for an unset one in a user-specified Space,
      # and nil for all three in an inheriting one.
      def airflows(record)
        user_specified = airflow_mode(record) == "user_specified"
        AIRFLOWS.to_h { |key| [key, user_specified ? record.fetch(key, 0.0).to_f : nil] }
      end

      # One Zone's sums over its Spaces' metrics and airflows. Airflow sums cover user-specified Spaces;
      # while any Space inherits, the sums are not meaningful and the imbalance is not evaluated.
      def zone(spaces)
        totals = sums(spaces.map { |space| space.fetch("metrics") }, TOTALS)
        inheriting = spaces.count { |space| space.fetch("airflow_mode") == "inheriting" }
        flows = AIRFLOWS.to_h do |key|
          [key, inheriting.zero? ? spaces.sum { |space| space.fetch("airflows").fetch(key) } : nil]
        end
        totals.merge("airflows" => flows, "inheriting_count" => inheriting,
                     "imbalanced" => imbalanced?(flows["v_sup_m3h"], flows["v_eta_m3h"]))
      end

      def imbalanced?(supply, extract)
        return false if supply.nil? || extract.nil?

        larger = [supply, extract].max
        larger.positive? && (supply - extract).abs > IMBALANCE_SHARE * larger
      end

      def sums(rows, keys)
        keys.to_h { |key| [key, rows.sum { |row| row.fetch(key) || 0.0 }] }
      end
    end
  end
end
