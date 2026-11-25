# frozen_string_literal: true

module PhComposer
  module Ducting
    GROUP_KIND = "#{FEATURE_ID}.group".freeze

    # The Ducting group: a record on a SketchUp Group that makes the Group hold drawn ducts and links it to one
    # Ventilator. Membership is the direct parent: an Edge is a duct only when the Group holding it carries this record.
    # The `dcg_` id proves identity in a reference. A pasted Group carries the record, id and Ventilator included, on a
    # new Group sharing its storage, so reads mark it copied and nothing re-issues it. The record claims its Group
    # (Records::EntityStore.claimed?), so no other feature turns it into something else.
    module Group
      STORE = Records::EntityStore.new(GROUP_KIND, :claims_entity => true)
      VENTILATOR_REFERENCE = Records::Reference.new(:key => "ventilator_id",
                                                    :target_kind => Mechanical::VENTILATOR_KIND, :cardinality => "one")
      RECORD_KIND = Records::RecordKind.new(
        :id => GROUP_KIND, :label => "Ducting group", :schema_version => 1, :id_prefix => "dcg",
        :fields => [Records::AuthoringFields.field(
          "ventilator_id", { "type" => %w[string null],
                             "description" => "The Ventilator its ducts connect to the outside; null while " \
                                              "unlinked, which blocks their export." }, :required => true
        )],
        :references => [VENTILATOR_REFERENCE]
      )

      module_function

      def identity(record)
        id = record && record["id"]
        Records::Identity.pattern(RECORD_KIND.id_prefix).match?(id.to_s) ? id : nil
      end

      def values(record)
        record ? RECORD_KIND.values(record) : {}
      end

      def new_record(id, ventilator_id)
        { "id" => id, "schema_version" => 1, "ventilator_id" => ventilator_id, "user_data" => {},
          "extension_data" => {} }
      end
    end
  end
end
