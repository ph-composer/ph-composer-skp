# frozen_string_literal: true

module PhComposer
  module Programs
    PROGRAM_KIND = "#{FEATURE_ID}.program"
    SCHEDULE_KIND = "#{FEATURE_ID}.schedule"
    EQUIPMENT_SET_KIND = "#{FEATURE_ID}.equipment_set"
    Fields = Records::AuthoringFields

    # The catalog fields every Programs kind shares: name, notes, datasheet links and a source whose kind may also
    # be `ph_composer_default`, the attribution of a residential default once it is written into the Model.
    module KindFields
      SOURCE_KINDS = %w[manual derived library ph_composer_default].freeze

      module_function

      def common
        Fields.common.map do |field|
          next field unless field.key == "source"

          kind = field.schema.fetch("properties").fetch("kind").merge("enum" => SOURCE_KINDS)
          Fields.field("source", field.schema.merge("properties" => field.schema.fetch("properties")
                                                                         .merge("kind" => kind)))
        end
      end

      # `own` after the shared fields, with the source snapshot declared over them all. A copied library row's
      # snapshot holds the library file's form of a field where `library` gives one (a Program's Schedules by
      # their record ids in the library, an Equipment Set's devices without ids).
      def with(own, library = {})
        snapshot = Fields.source_snapshot_schema(common + own)
        snapshot["properties"] = snapshot.fetch("properties").merge(DeepCopy.call(library))
        Fields.with_source_snapshot(common + own, snapshot)
      end
    end

    # A Schedule: one PH form by its type, shared by id across Programs. Values are what the form says, in
    # honeybee units; the honeybee ruleset is written at export.
    #
    #   fractional    start_h and end_h, the operating hours; fraction_on while operating, fraction_off otherwise
    #   activity      the same hours; watts_on and watts_off, W per person
    #   temperature   value_c, one constant (setbacks wait for the hourly editor)
    #   ventilation   periods: high, standard, basic and minimum in that order, each whole hours and a fraction of
    #                 the design flow, the hours totalling 24, as PHX names them
    #
    # Every type carries days_per_week (1 to 7) and weeks_per_year (1 to 52). Hours are whole: start_h 0 to 23,
    # end_h 0 to 24; an end before the start runs past midnight, and an end equal to the start has no operating
    # hours.
    module Schedule
      TYPES = %w[fractional activity temperature ventilation].freeze
      PERIODS = %w[high standard basic minimum].freeze
      HOURS = 24
      FORM_FIELDS = {
        "fractional" => %w[start_h end_h fraction_on fraction_off],
        "activity" => %w[start_h end_h watts_on watts_off],
        "temperature" => %w[value_c],
        "ventilation" => %w[periods]
      }.freeze
      # A new Schedule's form by type: on all day, honeybee's seated-adult 120 W, 20 °C, and full design flow all
      # day in the standard period.
      FORM_DEFAULTS = {
        "fractional" => { "start_h" => 0, "end_h" => 24, "fraction_on" => 1.0, "fraction_off" => 0.0 },
        "activity" => { "start_h" => 0, "end_h" => 24, "watts_on" => 120.0, "watts_off" => 120.0 },
        "temperature" => { "value_c" => 20.0 },
        "ventilation" => { "periods" => [{ "period" => "high", "hours" => 0, "fraction" => 1.0 },
                                         { "period" => "standard", "hours" => 24, "fraction" => 1.0 },
                                         { "period" => "basic", "hours" => 0, "fraction" => 0.5 },
                                         { "period" => "minimum", "hours" => 0, "fraction" => 0.3 }] }
      }.freeze
      FRACTION = { "type" => "number", "minimum" => 0, "maximum" => 1, "x-unit" => "fraction" }.freeze
      PERIOD = SchemaShapes.object({
        "period" => { "type" => "string", "enum" => PERIODS },
        "hours" => { "type" => "integer", "minimum" => 0, "maximum" => HOURS, "x-unit" => "h" },
        "fraction" => SchemaShapes.described(FRACTION, "The share of the design flow in this period.")
      })

      FIELDS = KindFields.with([
        Fields.field("type", { "type" => "string", "enum" => TYPES }, :required => true),
        Fields.field("days_per_week", { "type" => "integer", "minimum" => 1, "maximum" => 7 }, :required => true),
        Fields.field("weeks_per_year", { "type" => "integer", "minimum" => 1, "maximum" => 52 }, :required => true),
        Fields.field("start_h", { "type" => "integer", "minimum" => 0, "maximum" => HOURS - 1, "x-unit" => "h" }),
        Fields.field("end_h", { "type" => "integer", "minimum" => 0, "maximum" => HOURS, "x-unit" => "h" }),
        Fields.field("fraction_on", FRACTION),
        Fields.field("fraction_off", FRACTION),
        Fields.field("watts_on", { "type" => "number", "minimum" => 0, "x-unit" => "W/person" }),
        Fields.field("watts_off", { "type" => "number", "minimum" => 0, "x-unit" => "W/person" }),
        Fields.field("value_c", { "type" => "number", "minimum" => -273.15, "x-unit" => "C" }),
        Fields.field("periods", { "type" => "array", "items" => PERIOD, "minItems" => 4, "maxItems" => 4 })
      ])
      SNAPSHOT_SCHEMA = Fields.source_snapshot_schema(FIELDS)

      module_function

      # Every reason `values` is not one whole PH form: a field of another type, a missing one, periods out of
      # order, or ventilation hours that do not total 24.
      def problems(values)
        found = Fields.problems(values) + Fields.source_problems(values["source"], SNAPSHOT_SCHEMA)
        type = values.fetch("type")
        own = FORM_FIELDS.fetch(type)
        others = FORM_FIELDS.values.flatten.uniq - own
        stray = others.select { |key| values.key?(key) }
        found << "A #{type} Schedule does not carry #{stray.join(', ')}." unless stray.empty?
        missing = own.reject { |key| values.key?(key) }
        found << "A #{type} Schedule needs #{missing.join(', ')}." unless missing.empty?
        found.concat(period_problems(values["periods"])) if type == "ventilation" && values.key?("periods")
        found
      end

      def period_problems(periods)
        found = []
        unless periods.map { |row| row.fetch("period") } == PERIODS
          found << "Ventilation periods are #{PERIODS.join(', ')}, in that order."
        end
        total = periods.sum { |row| row.fetch("hours") }
        found << "Ventilation period hours total #{total}, not #{HOURS}." unless total == HOURS
        found
      end

      # A new Schedule's values: the type's form defaults, every day, every week, then `values`.
      def defaults(values)
        type = values.fetch("type", "fractional")
        { "type" => type, "days_per_week" => 7, "weeks_per_year" => 52 }
          .merge(DeepCopy.call(FORM_DEFAULTS.fetch(type))).merge(Fields.defaults(values))
      end

      # The values an update leaves: on a change of type the old form's fields go and the new form's defaults fill
      # any the update does not give. Answers the changed fields only, each nil where a field is removed.
      def changes(before, values)
        type = values["type"] || before.fetch("type")
        return values if type == before.fetch("type")

        removed = FORM_FIELDS.fetch(before.fetch("type")).to_h { |key| [key, nil] }
        removed.merge(DeepCopy.call(FORM_DEFAULTS.fetch(type))).merge(values)
      end

      KIND = Records::RecordKind.new(:id => SCHEDULE_KIND, :label => "Schedule", :schema_version => 1,
                                     :id_prefix => "sch", :fields => FIELDS, :validate => method(:problems))
    end

    # The 24-hour profile a Schedule's form draws and its full-load hours, for the editor's strip; pure, from the
    # values alone. Fractional and ventilation profiles are fractions, so they have full-load hours: the day's sum,
    # and over the year that sum on every operating day, days_per_week × weeks_per_year (the operating-day count
    # honeybee-ph's ScheduleRulesetPhProperties uses), days off counting nothing. An activity profile is W per
    # person and a temperature profile °C, levels rather than fractions, so their full-load hours are null.
    # Ventilation periods lie end to end from midnight, high first.
    module ScheduleProfile
      module_function

      def call(values)
        hours = profile(values)
        fraction = %w[fractional ventilation].include?(values.fetch("type"))
        daily = fraction ? hours.sum : nil
        annual = daily && daily * values.fetch("days_per_week") * values.fetch("weeks_per_year")
        { "hours" => hours, "daily_full_load_hours" => daily, "annual_full_load_hours" => annual }
      end

      def profile(values)
        case values.fetch("type")
        when "fractional" then operating(values, values.fetch("fraction_on"), values.fetch("fraction_off"))
        when "activity" then operating(values, values.fetch("watts_on"), values.fetch("watts_off"))
        when "temperature" then Array.new(Schedule::HOURS, values.fetch("value_c"))
        else values.fetch("periods").flat_map { |row| Array.new(row.fetch("hours"), row.fetch("fraction")) }
        end
      end

      def operating(values, on, off)
        (0...Schedule::HOURS).map { |hour| operating?(values.fetch("start_h"), values.fetch("end_h"), hour) ? on : off }
      end

      # Whether `hour` (0 to 23) is inside the operating hours from `start` to `stop`.
      def operating?(start, stop, hour)
        return hour >= start && hour < stop if start < stop
        return hour >= start || hour < stop if start > stop

        false
      end
    end
  end
end
