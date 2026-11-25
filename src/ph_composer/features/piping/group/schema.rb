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

      def values(record)
        record ? RECORD_KIND.values(record) : {}
      end

      def new_record(id, system_id)
        LINE_GROUP.new_group(id, system_id)
      end

      def piping_group?(entity)
        entity.is_a?(Sketchup::Group) && STORE.marks?(entity)
      end

      def contents(entity)
        LineGroups.contents(entity)
      end

      # The record as stored (LineGroups.read); `store` is the Group's or the Edge's.
      def read(entity, store = STORE)
        LineGroups.read(entity, store)
      end
    end
  end
end
