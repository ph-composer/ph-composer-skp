# frozen_string_literal: true

module PhComposer
  module Piping
    GROUP_KIND = "#{FEATURE_ID}.group".freeze

    # The Piping group: a record on a SketchUp Group that makes the Group hold drawn pipes and links it to one Hot
    # Water System. Membership is the direct parent: an Edge is a pipe only when the Group holding it carries this
    # record. The `ppg_` id proves identity in a reference, as an Edge's does. A pasted Group carries the record, id
    # included, on a new Group sharing its storage, so reads mark it copied and nothing re-issues it. The record
    # claims its Group (Records::EntityStore.claimed?), so no other feature turns it into something else.
    module Group
      STORE = Records::EntityStore.new(GROUP_KIND, :claims_entity => true)
      ID_PATTERN = Records::Identity.pattern("ppg")
      SYSTEM_REFERENCE = Records::Reference.new(:key => "hot_water_system_id",
                                                :target_kind => Mechanical::HOT_WATER_SYSTEM_KIND,
                                                :cardinality => "one")
      RECORD_KIND = Records::RecordKind.new(
        :id => GROUP_KIND, :label => "Piping group", :schema_version => 1, :id_prefix => "ppg",
        :fields => [Records::AuthoringFields.field(
          "hot_water_system_id", { "type" => %w[string null],
                                   "description" => "The Hot Water System its pipes serve; null while unlinked, " \
                                                    "which blocks their export." }, :required => true
        )],
        :references => [SYSTEM_REFERENCE]
      )

      module_function

      def validate!(record)
        found = RECORD_KIND.problems(record)
        return record if found.empty?

        raise CodedError.new("validation.failed", "A Piping group record is invalid: #{found.first}.",
                             "findings" => found)
      end

      def identity(record)
        id = record && record["id"]
        ID_PATTERN.match?(id.to_s) ? id : nil
      end

      def values(record)
        record ? RECORD_KIND.values(record) : {}
      end

      def new_record(id, system_id)
        { "id" => id, "schema_version" => 1, "hot_water_system_id" => system_id, "user_data" => {},
          "extension_data" => {} }
      end

      # `record` as the engine's reference scan reads it: a metadata map that is not a JSON object holds no extension
      # envelope and so names nothing, and is left out rather than failing every delete in the Model.
      def scannable(record)
        record.reject { |key, value| %w[user_data extension_data].include?(key) && !value.is_a?(Hash) }
      end

      def piping_group?(entity)
        entity.is_a?(Sketchup::Group) && STORE.marks?(entity)
      end

      def contents(entity)
        if entity.is_a?(Sketchup::Group)
          entity.entities
        elsif entity.is_a?(Sketchup::ComponentInstance)
          entity.definition.entities
        end
      end

      # The record as stored when its text is a JSON object, as `[record, nil]`; `[nil, nil]` with none and
      # `[nil, problem]` for anything else, which a read reports and a write refuses. It never raises for what is
      # stored. `store` is the Group's or the Edge's.
      def read(entity, store = STORE)
        value = entity.get_attribute(store.dictionary, store.key)
        return [nil, nil] if value.nil?
        return [nil, "The #{store.dictionary} record is not JSON text."] unless value.is_a?(String)

        record = store.read(entity)
        record.is_a?(Hash) ? [record, nil] : [nil, "The #{store.dictionary} record is not a JSON object."]
      rescue CodedError => error
        raise unless error.code == "record.unreadable"

        [nil, error.message]
      end
    end
  end
end
