# frozen_string_literal: true

module PhComposer
  module Programs
    DWELLING_KIND = "#{FEATURE_ID}.dwelling"

    # A Dwelling: one or more Zones counted as one dwelling unit, or as `units` identical ones (honeybee-ph's
    # PhDwellings). Its Zones name it through their assignment; its counts are each Zone's, summed, unless it holds
    # its own, which only switching Single dwelling off gives it. The counts and the Set are optional: an edit to
    # null removes one, which reads as none. A Dwelling with no Equipment Set of its own uses
    # the Model's default Set.
    module Dwelling
      COUNT = { "type" => %w[number null], "minimum" => 0 }.freeze
      FIELDS = KindFields.with([
        Fields.field("units", { "type" => "integer", "minimum" => 1,
                                "description" => "How many identical dwelling units it counts as." },
                     :required => true),
        Fields.field("bedrooms", COUNT.merge("description" => "Its own bedroom count; absent or null sums its " \
                                                              "Zones'.")),
        Fields.field("occupants", COUNT.merge("description" => "Its own occupant count; absent or null sums its " \
                                                               "Zones', else the Phius rule, bedrooms + units.")),
        Fields.field("equipment_set_id", SchemaShapes.id("eqs", "Its Equipment Set; absent or null for the Model's " \
                                                                "default.", :nullable => true))
      ])
      REFERENCES = [Records::Reference.new(:key => "equipment_set_id", :target_kind => EQUIPMENT_SET_KIND,
                                           :cardinality => "one", :required => false)].freeze
      SNAPSHOT_SCHEMA = FIELDS.find { |field| field.key == "source" }.schema.dig("properties", "snapshot")

      module_function

      def problems(values)
        Fields.problems(values) + Fields.source_problems(values["source"], SNAPSHOT_SCHEMA)
      end

      def defaults(values)
        { "units" => 1, "bedrooms" => nil, "occupants" => nil,
          "equipment_set_id" => nil }.merge(Fields.defaults(values))
      end

      KIND = Records::RecordKind.new(:id => DWELLING_KIND, :label => "Dwelling", :schema_version => 1,
                                     :id_prefix => "dwl", :fields => FIELDS, :references => REFERENCES,
                                     :validate => method(:problems))
    end

    # The two structured extensions occupancy is stored in (context/CONTRACTS.md, "Occupancy"). Both are `required`:
    # the Program export claims them (ProgramExport), so a payload on an exported Zone or Segment is read, and one this
    # version does not understand blocks the export rather than being left out.
    #
    #   zone_assignment   on each Zone: its Program, Dwelling, Equipment Set and counts. Absent, or every field
    #                     null, the Zone is unassigned.
    #   segment           on each Building Segment: Single dwelling, its Zones' default Program, and while single the
    #                     house's bedrooms, occupants and Equipment Set. Absent, Single dwelling is on.
    module Occupancy
      ZONE_NAMESPACE = "#{FEATURE_ID}.zone_assignment"
      SEGMENT_NAMESPACE = "#{FEATURE_ID}.segment"
      SEGMENT_KIND = Zones::Options::SEGMENT_KIND
      ZONE_FIELDS = %w[program_id dwelling_id equipment_set_id bedrooms occupants].freeze
      SEGMENT_FIELDS = %w[single_dwelling default_program_id bedrooms occupants equipment_set_id].freeze
      UNASSIGNED = ZONE_FIELDS.to_h { |key| [key, nil] }.freeze
      SEGMENT_DEFAULTS = { "single_dwelling" => true, "default_program_id" => nil, "bedrooms" => nil,
                           "occupants" => nil, "equipment_set_id" => nil }.freeze
      ID_PATTERNS = { "program_id" => /\Apgm_[A-Za-z0-9]{12}\z/, "dwelling_id" => /\Adwl_[A-Za-z0-9]{12}\z/,
                      "default_program_id" => /\Apgm_[A-Za-z0-9]{12}\z/,
                      "equipment_set_id" => /\Aeqs_[A-Za-z0-9]{12}\z/ }.freeze
      TARGETS = { "program_id" => PROGRAM_KIND, "dwelling_id" => DWELLING_KIND, "default_program_id" => PROGRAM_KIND,
                  "equipment_set_id" => EQUIPMENT_SET_KIND }.freeze

      module_function

      def references(fields)
        fields.filter_map do |key|
          target = TARGETS[key]
          target && { "path" => "$.#{key}", "target_kind" => target, "cardinality" => "one" }
        end
      end

      # Every reason `payload` is not a whole payload of `fields`: each one present, the ids of their kind or null,
      # the counts numbers at least 0 or null, and Single dwelling true or false.
      def problems(payload, fields)
        extra = payload.keys - fields
        missing = fields - payload.keys
        found = extra.empty? ? [] : ["unknown fields #{extra.sort.join(', ')}"]
        found << "missing fields #{missing.join(', ')}" unless missing.empty?
        (fields & payload.keys).each do |key|
          value = payload[key]
          next if value.nil? && key != "single_dwelling"

          if key == "single_dwelling"
            found << "single_dwelling must be true or false" unless [true, false].include?(value)
          elsif ID_PATTERNS.key?(key)
            found << "#{key} must be a #{TARGETS.fetch(key).split('.').last} id or null" unless ID_PATTERNS
                                                                                                .fetch(key)
                                                                                                .match?(value.to_s)
          elsif !count?(value)
            found << "#{key} must be a number of at least 0, or null"
          end
        end
        found
      end

      def count?(value)
        value.is_a?(Numeric) && value.real? && value.to_f.finite? && value >= 0
      end

      ZONE_EXTENSION = Records::Extension.new(:namespace => ZONE_NAMESPACE, :schema_version => 1,
                                              :references => references(ZONE_FIELDS),
                                              :export_relevance => "required",
                                              :validate => ->(payload) { problems(payload, ZONE_FIELDS) })
      SEGMENT_EXTENSION = Records::Extension.new(:namespace => SEGMENT_NAMESPACE, :schema_version => 1,
                                                 :references => references(SEGMENT_FIELDS),
                                                 :export_relevance => "required",
                                                 :validate => ->(payload) { problems(payload, SEGMENT_FIELDS) })

      # The understood payload of `namespace` in a record's `extension_data`, or nil for none, or one this version
      # does not understand.
      def payload(extension_data, namespace, catalog)
        envelope = extension_data.fetch(namespace, nil)
        return nil unless envelope

        status = Records::Extension.status(envelope, catalog.extension(namespace))
        status == "understood" ? DeepCopy.call(envelope.fetch("payload")) : nil
      end

      # A Zone's assignment, unassigned where it stores none.
      def zone_values(extension_data, catalog)
        payload(extension_data, ZONE_NAMESPACE, catalog) || UNASSIGNED.dup
      end

      # A Segment's occupancy settings, the defaults where it stores none.
      def segment_values(extension_data, catalog)
        payload(extension_data, SEGMENT_NAMESPACE, catalog) || SEGMENT_DEFAULTS.dup
      end

      def unassigned?(values)
        ZONE_FIELDS.all? { |key| values[key].nil? }
      end
    end
  end
end
