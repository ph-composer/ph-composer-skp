# frozen_string_literal: true

module PhComposer
  module Piping
    module Runs
      # The recirculation sum per Hot Water System, worked out as honeybee-ph's `PhHotWaterSystem` works out
      # `recirc_temp` and `recirc_hours` (honeybee_phhvac/hot_water_system.py and hot_water_piping.py in the pinned
      # wheel): each run, one pipe element, takes the length-weighted mean of its pipes' temperature and hours; the
      # System takes the length-weighted mean of its runs' means, and truncates the hours toward zero as `int()` does.
      # With no recirculation pipe, 60.0 and 24.
      #
      # The arithmetic copies honeybee-ph's step for step so the values equal what the export reloads to, float noise
      # included: a segment's length is the square root of its three squared differences added in order, as
      # ladybug-geometry's Vector3D magnitude is, and every sum adds left to right, as CPython 3.11's `sum` does
      # (the runtime's Python). Ruby's Array#sum compensates, so it is not used here. Runs are added in identifier
      # order and a run's pipes in segment identifier order: the canonical HBJSON is written with its keys sorted, and
      # honeybee-ph keys recirculation elements and segments by identifier, so that is the order a reloaded system sums
      # them in, and the export's Python section adds them in the same order so its system sums them alike.
      module Recirculation
        DEFAULT_TEMPERATURE_C = 60.0
        DEFAULT_HOURS = 24
        Element = Struct.new(:length_m, :temperature_c, :hours, keyword_init: true)

        module_function

        # `runs` are one System's recirculation runs, in any order.
        def call(runs)
          elements = runs.sort_by(&:identifier).map { |run| element(run) }
          total = add(elements.map(&:length_m))
          result = { "recirculation_length_m" => total, "recirculation_temperature_c" => DEFAULT_TEMPERATURE_C,
                     "recirculation_hours" => DEFAULT_HOURS, "from_piping" => !elements.empty? }
          return result if elements.empty? || total.zero?

          result.merge(
            "recirculation_temperature_c" => add(elements.map { |one| one.temperature_c * one.length_m }) / total,
            "recirculation_hours" => (add(elements.map { |one| one.hours * one.length_m }) / total).to_i
          )
        end

        # One run as one pipe element: its length and its pipes' length-weighted temperature and hours, 60.0 and 24.0
        # when it has no length, as honeybee-ph's element does.
        def element(run)
          facts = run.facts.zip(run.segments).sort_by(&:last).map(&:first)
          lengths = facts.map { |fact| segment_length(*fact.points_m) }
          length = add(lengths)
          return Element.new(:length_m => length, :temperature_c => 60.0, :hours => 24.0) if length.zero?

          temperature = add(facts.zip(lengths).map { |fact, each| each * fact.values.fetch("water_temp_c") })
          hours = add(facts.zip(lengths).map { |fact, each| each * fact.values.fetch("daily_period") })
          Element.new(:length_m => length, :temperature_c => temperature / length, :hours => hours / length)
        end

        def segment_length(start, finish)
          x, y, z = finish.zip(start).map { |end_value, start_value| end_value - start_value }
          Math.sqrt((x**2) + (y**2) + (z**2))
        end

        def add(values)
          values.inject(0.0) { |sum, value| sum + value }
        end
      end
    end
  end
end
