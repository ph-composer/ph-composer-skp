# frozen_string_literal: true

module PhComposer
  module Certification
    # The Phius certification settings of one Building Segment: a structured extension on the Segment record
    # (context/CONTRACTS.md, "Building Segment settings"). Zones' Save stages it like every settings section, so
    # this feature writes no record. A Segment with no payload, or one this version does not understand, reads
    # the defaults, which are honeybee-ph's own (honeybee_ph/phius.py, PhiusCertification).
    module Segment
      NAMESPACE = "#{FEATURE_ID}.segment"
      SEGMENT_KIND = Zones::Options::SEGMENT_KIND
      # Each field's values, in the order the section offers them. The translation maps each to honeybee-ph's
      # PhiusCertification enums (python/ph_composer_translation/certification_sections.py). The programs are
      # the Phius ones of the pinned honeybee-ph PhiusBuildingCertificationProgram, which stops at Phius 2021.
      CHOICES = {
        "category" => %w[residential non_residential],
        "program" => %w[phius_2021_core phius_2021_zero phius_2018_core phius_2018_zero phius_2018 phius_2015],
        "use" => %w[residential office_administrative school other undefined_unfinished],
        "status" => %w[in_planning under_construction complete],
        "type" => %w[new_construction retrofit mixed]
      }.transform_values(&:freeze).freeze
      FIELDS = CHOICES.keys.freeze
      DEFAULTS = { "category" => "residential", "program" => "phius_2021_core", "use" => "residential",
                   "status" => "in_planning", "type" => "new_construction" }.freeze

      module_function

      # Every reason `payload` is not a whole certification payload: each of the five fields, and nothing else,
      # holding one of its values.
      def problems(payload)
        extra = payload.keys - FIELDS
        found = extra.empty? ? [] : ["unknown fields #{extra.sort.join(', ')}"]
        found + FIELDS.filter_map do |field|
          next nil if CHOICES.fetch(field).include?(payload[field])

          "#{field} must be one of #{CHOICES.fetch(field).join(', ')}"
        end
      end

      EXTENSION = Records::Extension.new(:namespace => NAMESPACE, :schema_version => 1,
                                         :export_relevance => "required", :validate => method(:problems))

      # One Segment's settings as other features read them: the stored payload when it is understood, else the
      # defaults, with whether a payload was used and the envelope's status, null only when the Segment stores
      # none: a stored null or other unreadable envelope is `unsupported`, as a record read says.
      def read(request, id)
        record = request.engine.find(SEGMENT_KIND, id)
        data = record.fetch("extension_data", {})
        envelope = data[NAMESPACE]
        installed = request.registry.catalog.extension(NAMESPACE)
        status = data.key?(NAMESPACE) ? Records::Extension.status(envelope, installed) : nil
        payload = status == "understood" ? envelope.fetch("payload") : nil
        { "id" => id, "values" => values(payload), "stored" => !payload.nil?, "extension_status" => status }
      end

      # The five values, from an understood payload or the defaults.
      def values(payload)
        payload ? DeepCopy.call(payload.slice(*FIELDS)) : DEFAULTS.dup
      end
    end
  end
end
