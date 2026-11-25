# frozen_string_literal: true

module PhComposer
  module Ducting
    module Group
      # The Ducting group reference target, over the shared line-group layer (LineGroups::GroupTarget): a reference
      # names the Group by its root-to-Group persistent-id path and its `dcg_` id.
      REFERENCE = {
        "type" => "object", "additionalProperties" => false, "required" => %w[group_id group_path],
        "properties" => {
          "group_id" => { "type" => "string", "description" => "The Ducting group's dcg_ id." },
          "group_path" => LineGroups::PATH.merge("minItems" => 1,
                                                 "description" => "The root-to-Group persistent-id path, one per " \
                                                                  "placement.")
        }
      }.freeze

      TARGET = Records::ReferenceTarget.new(
        :id => GROUP_KIND, :label => "Ducting group", :schema_version => 1, :values => RECORD_KIND.values_schema,
        :occurrence => REFERENCE, :records => ->(model) { LineGroups::GroupTarget.entries(LINE_GROUP, model) },
        :validate => ->(record) { RECORD_KIND.problems(record) }, :references => RECORD_KIND.references,
        :locate => lambda { |model, reference, mutable:, index: nil|
          LineGroups::GroupTarget.locate(LINE_GROUP, model, reference, :mutable => mutable, :index => index)
        },
        :locate_index => ->(_model) { Zones::ChildLookup.new }
      )
    end
  end
end
