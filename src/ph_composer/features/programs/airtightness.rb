# frozen_string_literal: true

module PhComposer
  module Programs
    # The airtightness of one Building Segment: its blower-door test result and its wind exposure, a structured
    # extension on the Segment record (context/CONTRACTS.md, "Building Segment settings"). Zones' Save stages it
    # like every settings section, so this feature writes no record. A Segment with no payload, or one this
    # version does not understand, reads the defaults: no test result, and honeybee-ph's own wind exposure.
    module Airtightness
      NAMESPACE = "#{FEATURE_ID}.airtightness"
      SEGMENT_KIND = Zones::Options::SEGMENT_KIND
      # n50 is air changes per hour at 50 Pa over the net volume; q50 is m³/h per m² of envelope at 50 Pa.
      BASES = %w[n50 q50].freeze
      # The seven honeybee-ph PhWindExposureType values (honeybee_ph/bldg_segment.py), in the order the section
      # offers them; the translation maps each (python/ph_composer_translation/airtightness_sections.py).
      WIND_EXPOSURES = %w[several_sides_no_screening several_sides_moderate_screening several_sides_high_screening
                          one_side_no_screening one_side_moderate_screening one_side_high_screening
                          user_defined].freeze
      FIELDS = %w[basis value wind_exposure].freeze
      DEFAULTS = { "basis" => "n50", "value" => nil, "wind_exposure" => "several_sides_no_screening" }.freeze

      module_function

      # Every reason `payload` is not a whole airtightness payload: the three fields and nothing else, the value
      # a finite number greater than zero or null for no test result.
      def problems(payload)
        extra = payload.keys - FIELDS
        found = extra.empty? ? [] : ["unknown fields #{extra.sort.join(', ')}"]
        found << "basis must be one of #{BASES.join(', ')}" unless BASES.include?(payload["basis"])
        found << "value must be a number greater than 0, or null" unless value?(payload)
        unless WIND_EXPOSURES.include?(payload["wind_exposure"])
          found << "wind_exposure must be one of #{WIND_EXPOSURES.join(', ')}"
        end
        found
      end

      # Whether the payload holds a value: a finite number greater than zero, or null.
      def value?(payload)
        return false unless payload.key?("value")

        value = payload["value"]
        value.nil? || (value.is_a?(Numeric) && value.real? && value.to_f.finite? && value.positive?)
      end

      EXTENSION = Records::Extension.new(:namespace => NAMESPACE, :schema_version => 1,
                                         :export_relevance => "required", :validate => method(:problems))

      # One Segment's airtightness as other features read it: the stored payload when it is understood, else the
      # defaults, with whether a payload was used and the envelope's status, null only when the Segment stores
      # none: a stored null or other unreadable envelope is `unsupported`, as a record read says.
      def read(request, id)
        record = request.engine.find(SEGMENT_KIND, id)
        data = record.fetch("extension_data", {})
        installed = request.registry.catalog.extension(NAMESPACE)
        status = data.key?(NAMESPACE) ? Records::Extension.status(data[NAMESPACE], installed) : nil
        payload = status == "understood" ? data.fetch(NAMESPACE).fetch("payload") : nil
        { "id" => id, "values" => values(payload), "stored" => !payload.nil?, "extension_status" => status }
      end

      # The three values, from an understood payload or the defaults.
      def values(payload)
        payload ? DeepCopy.call(payload.slice(*FIELDS)) : DEFAULTS.dup
      end
    end
  end
end
