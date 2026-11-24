# frozen_string_literal: true

module PhComposer
  module Mechanical
    # The mechanical settings of one Building Segment: whether it has mechanical cooling, its mechanical room
    # temperature and four summer ventilation values, a structured extension on the Segment record
    # (context/CONTRACTS.md, "Building Segment settings"). Zones' Save stages it like every settings section, so this
    # feature writes no record. A Segment with no payload, or one this version does not understand, reads the
    # defaults, which are honeybee-ph's own (honeybee_ph/bldg_segment.py: SetPoints, BldgSegment, SummerVentilation).
    # honeybee-ph's other seven summer ventilation values, the extract system and night flush ones, are not stored:
    # the export leaves them at their defaults.
    module SegmentSettings
      NAMESPACE = "#{FEATURE_ID}.segment"
      SEGMENT_KIND = Zones::Options::SEGMENT_KIND
      # honeybee-ph's PhVentilationSummerBypassMode values, in its order; the translation maps each
      # (python/ph_composer_translation/mechanical_segment_sections.py).
      BYPASS_MODES = %w[none temperature_controlled enthalpy_controlled always].freeze
      # Air changes per hour, each null-able only where honeybee-ph's default is None.
      RATES = { "ventilation_system_ach" => true, "daytime_window_ach" => false,
                "nighttime_window_ach" => false }.freeze
      FIELDS = (%w[mechanical_cooling mech_room_temp_c summer_bypass_mode] + RATES.keys).freeze
      DEFAULTS = { "mechanical_cooling" => false, "mech_room_temp_c" => 20.0, "summer_bypass_mode" => "always",
                   "ventilation_system_ach" => nil, "daytime_window_ach" => 0.0,
                   "nighttime_window_ach" => 0.0 }.freeze

      module_function

      # Every reason `payload` is not a whole mechanical settings payload: the six fields and nothing else, each of
      # its type, the rates 0 or more.
      def problems(payload)
        extra = payload.keys - FIELDS
        missing = FIELDS - payload.keys
        found = []
        found << "unknown fields #{extra.sort.join(', ')}" unless extra.empty?
        found << "missing fields #{missing.join(', ')}" unless missing.empty?
        found << "mechanical_cooling must be true or false" unless [true, false].include?(payload["mechanical_cooling"])
        found << "mech_room_temp_c must be a number" unless finite?(payload["mech_room_temp_c"])
        unless BYPASS_MODES.include?(payload["summer_bypass_mode"])
          found << "summer_bypass_mode must be one of #{BYPASS_MODES.join(', ')}"
        end
        found + RATES.filter_map do |field, nullable|
          value = payload[field]
          next if (nullable && value.nil?) || (finite?(value) && value >= 0)

          "#{field} must be a number of 0 or more#{nullable ? ', or null' : ''}"
        end
      end

      def finite?(value)
        value.is_a?(Numeric) && value.real? && value.to_f.finite?
      end

      EXTENSION = Records::Extension.new(:namespace => NAMESPACE, :schema_version => 1,
                                         :export_relevance => "required", :validate => method(:problems))

      # One Segment's settings as other features read them: the stored payload when it is understood, else the
      # defaults, with whether a payload was used and the envelope's status, null only when the Segment stores
      # none: a stored null or other unreadable envelope is `unsupported`, as a record read says.
      def read(request, id)
        record = request.engine.find(SEGMENT_KIND, id)
        payload, status = stored(request, record)
        { "id" => id, "values" => values(payload), "stored" => !payload.nil?, "extension_status" => status }
      end

      # A Segment record's understood payload, or nil, and its envelope's status.
      def stored(request, record)
        data = record.fetch("extension_data", {})
        installed = request.registry.catalog.extension(NAMESPACE)
        status = data.key?(NAMESPACE) ? Records::Extension.status(data[NAMESPACE], installed) : nil
        [status == "understood" ? data.fetch(NAMESPACE).fetch("payload") : nil, status]
      end

      # The six values, from an understood payload or the defaults.
      def values(payload)
        payload ? DeepCopy.call(payload.slice(*FIELDS)) : DEFAULTS.dup
      end
    end
  end
end
