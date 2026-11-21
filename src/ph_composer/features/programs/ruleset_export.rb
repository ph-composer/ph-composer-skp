# frozen_string_literal: true

require "date"

module PhComposer
  module Programs
    # Pure: what one Schedule's PH form says a honeybee ScheduleRuleset is, worked out in Ruby so the translation
    # only builds it (python/ph_composer_translation/program_sections.py). The operating day is the form's 24-hour
    # profile (ScheduleProfile). It applies on the first `days_per_week` days from Monday (5: Monday to Friday; 6:
    # to Saturday) and over the year less its weeks off, which are one contiguous block centred on 1 August, a
    # school year's summer closure (C4a-9). Every other day is the off day: the form's level outside its operating
    # hours (fraction_off, watts_off) or, for ventilation, its minimum period's fraction all day. A Schedule that
    # runs every day of every week has no off day, and its ruleset is the operating day alone.
    #
    # A temperature Schedule is one constant, every day. A ventilation Schedule also carries honeybee-ph's four
    # operating periods, high, standard, basic and minimum end to end from midnight, which PHX reads as the
    # ventilation utilization pattern (C4a-10); occupancy and lighting Schedules carry none until the honeybee-ph
    # and PHX fix for F4a-13 (Q4a-08), so PHX reads their hourly values.
    module RulesetExport
      WEEKDAYS = %w[monday tuesday wednesday thursday friday saturday sunday].freeze
      TYPE_LIMITS = { "fractional" => "Fractional", "activity" => "Activity Level", "temperature" => "Temperature",
                      "ventilation" => "Fractional" }.freeze
      # 1 August in a 365-day year, which honeybee's rules use.
      CLOSURE_CENTRE = Date.new(2017, 8, 1).yday
      DAYS_PER_YEAR = 365

      module_function

      # The export record of Schedule `values` (its record values, with `id`), named `name`.
      def call(values, name)
        type = values.fetch("type")
        days, weeks = type == "temperature" ? [7, 52] : values.values_at("days_per_week", "weeks_per_year")
        every_day = days == 7 && weeks == 52
        { "id" => values.fetch("id"), "name" => name, "type_limit" => TYPE_LIMITS.fetch(type),
          "operating_day" => ScheduleProfile.profile(values),
          "off_day" => every_day ? nil : Array.new(Schedule::HOURS, off_value(values)),
          "operating_weekdays" => WEEKDAYS.first(days), "operating_dates" => operating_dates(weeks),
          "days_per_week" => days, "weeks_per_year" => weeks, "operating_periods" => periods(values) }
      end

      # A constant temperature Schedule that stands in for a set point a Program gives as a number.
      def constant(id, name, value_c)
        call({ "id" => id, "type" => "temperature", "value_c" => value_c }, name)
      end

      def off_value(values)
        case values.fetch("type")
        when "fractional" then values.fetch("fraction_off")
        when "activity" then values.fetch("watts_off")
        when "temperature" then values.fetch("value_c")
        else values.fetch("periods").find { |row| row.fetch("period") == "minimum" }.fetch("fraction")
        end
      end

      # The date ranges, `[[month, day], [month, day]]` inclusive, over which the operating day applies: the whole
      # year, or the year either side of the weeks off. The block is moved inside the year when centring it on 1
      # August would run past 31 December.
      def operating_dates(weeks)
        off = (52 - weeks) * 7
        return [[[1, 1], [12, 31]]] if off.zero?

        first = [CLOSURE_CENTRE - (off / 2), 1].max
        first = DAYS_PER_YEAR - off + 1 if first + off - 1 > DAYS_PER_YEAR
        last = first + off - 1
        [[1, first - 1], [last + 1, DAYS_PER_YEAR]].select { |from, to| from <= to }
                                                   .map { |from, to| [month_day(from), month_day(to)] }
      end

      def month_day(day_of_year)
        date = Date.new(2017, 1, 1) + (day_of_year - 1)
        [date.month, date.day]
      end

      # A ventilation Schedule's four periods end to end from midnight, as honeybee-ph's DailyOperationPeriod
      # names them; none for any other type.
      def periods(values)
        return [] unless values.fetch("type") == "ventilation"

        start = 0
        values.fetch("periods").map do |row|
          period = { "name" => row.fetch("period"), "start_hour" => start, "end_hour" => start + row.fetch("hours"),
                     "fraction" => row.fetch("fraction") }
          start += row.fetch("hours")
          period
        end
      end
    end
  end
end
