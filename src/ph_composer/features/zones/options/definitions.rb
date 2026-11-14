# frozen_string_literal: true

require "digest"

module PhComposer
  module Zones
    # The Model owns the choices; labels in portable evidence are recovery snapshots only.
    module Options
      PREFIX = "#{FEATURE_ID}.options"
      SEGMENT_KIND = "#{FEATURE_ID}.building_segment"
      LEVEL_KIND = "#{FEATURE_ID}.level"
      SETTINGS_KIND = "#{FEATURE_ID}.option_settings"
      SETTINGS_ID = "zop_AAAAAAAAAAAA"
      STAMP_KIND = "#{FEATURE_ID}.membership_stamp"
      COLOUR = SchemaShapes::HEX_COLOUR
      NAME = { "type" => "string", "minLength" => 1 }.freeze
      FIELDS = [Records::Field.new(:key => "name", :schema => NAME, :required => true),
                Records::Field.new(:key => "colour", :schema => COLOUR, :required => true)].freeze
      # Both option kinds share one follow-up, so a batch writing a Segment and a Level rewrites each Zone once.
      EVIDENCE_FOLLOW_UP = ->(request, proposal) { Options.rewrite_evidence(request, proposal) }
      SEGMENTS = Records::RecordKind.new(
        :id => SEGMENT_KIND, :label => "Building Segment", :schema_version => 1, :id_prefix => "bsg",
        :fields => FIELDS + [Records::Field.new(:key => "export_identifier", :required => true,
                                                :schema => { "type" => "string", "pattern" => "^bseg_[a-zA-Z0-9_]+$",
                                                             "maxLength" => 100 })],
        :metadata_follow_up => EVIDENCE_FOLLOW_UP
      )
      LEVELS = Records::RecordKind.new(:id => LEVEL_KIND, :label => "Level", :schema_version => 1,
                                       :id_prefix => "lvl", :fields => FIELDS,
                                       :metadata_follow_up => EVIDENCE_FOLLOW_UP)
      SETTINGS = Records::RecordKind.new(
        :id => SETTINGS_KIND, :label => "Zone option settings", :schema_version => 1, :id_prefix => "zop",
        :owner_writes_metadata => true,
        :fields => [Records::Reference.new(:key => "default_segment_id", :target_kind => SEGMENT_KIND,
                                           :cardinality => "one", :required => true),
                    Records::Field.new(:key => "source_model_id", :required => true,
                                       :schema => { "type" => "string", "minLength" => 1 })]
      )
      CHOICE_REFERENCES = [
        Records::Reference.new(:key => "building_segment_id", :target_kind => SEGMENT_KIND, :cardinality => "one"),
        Records::Reference.new(:key => "level_id", :target_kind => LEVEL_KIND, :cardinality => "one")
      ].freeze
      KINDS = { "building_segment" => SEGMENTS, "level" => LEVELS }.freeze

      module_function

      def name_key(name)
        name.strip.downcase.gsub(/[[:space:]_-]+/, " ")
      end

      def records(engine, kind, proposal = nil)
        ids = engine.ids(kind)
        ids += proposal.writes.select { |write| write.kind == kind && write.after }.map(&:id) if proposal
        ids.uniq.sort.filter_map do |id|
          change = proposal&.find(kind, id)
          next if change && change.after.nil?

          engine.find(kind, id, :change_set => proposal&.record_changes)
        end
      end

      def settings(engine, proposal = nil)
        return nil unless engine.ids(SETTINGS_KIND).include?(SETTINGS_ID) || proposal&.find(SETTINGS_KIND, SETTINGS_ID)

        engine.find(SETTINGS_KIND, SETTINGS_ID, :change_set => proposal&.record_changes)
      end

      def export_identifier(name)
        "bseg_#{Digest::SHA256.hexdigest(name.encode('UTF-8'))[0, 16]}"
      end

      def validate_collection!(rows, collection)
        seen = {}
        exports = {}
        rows.each do |row|
          kind = KINDS.fetch(collection)
          problems = kind.problems(row)
          refuse("validation.failed", problems.first) unless problems.empty?
          key = name_key(row.fetch("name"))
          refuse("validation.failed", "Enter a nonempty option name") if key.empty?
          refuse("zone.option_duplicate", "An equivalent option already exists: #{seen[key]}") if seen[key]
          seen[key] = row.fetch("name")
          next unless collection == "building_segment"

          identifier = row.fetch("export_identifier")
          if exports[identifier] && exports[identifier] != row.fetch("id")
            refuse("zone.option_export_conflict", "Two Building Segments share an export identity; map to one survivor")
          end
          exports[identifier] = row.fetch("id")
        end
      end

      def refuse(code, message)
        raise CodedError.new(code, "#{message}. Nothing was written.")
      end

      def resolve(engine, record, proposal = nil)
        return record.values_at("building_segment", "level") if record.fetch("schema_version") == 1

        segment = engine.find(SEGMENT_KIND, record.fetch("building_segment_id"),
                              :change_set => proposal&.record_changes)
        level = record["level_id"] && engine.find(LEVEL_KIND, record.fetch("level_id"),
                                                  :change_set => proposal&.record_changes)
        [segment, level]
      end

      def evidence(engine, record, proposal = nil)
        segment, level = resolve(engine, record, proposal)
        { "source_model_id" => settings(engine, proposal)&.fetch("source_model_id"),
          "building_segment" => segment, "level" => level }
      end

      def display(engine, record)
        return {} if record.fetch("schema_version") == 1

        evidence = record.fetch("choice_evidence", {})
        choices = [[SEGMENT_KIND, "building_segment"], [LEVEL_KIND, "level"]].to_h do |kind, field|
          id = record["#{field}_id"]
          option = begin
            id && engine.find(kind, id)
          rescue CodedError
            evidence[field]
          end
          [field, option]
        end
        { "building_segment" => choices["building_segment"]&.fetch("name", nil),
          "level" => choices["level"]&.fetch("name", nil),
          "building_segment_colour" => choices["building_segment"]&.fetch("colour", nil),
          "level_colour" => choices["level"]&.fetch("colour", nil) }
      end
    end
  end
end
