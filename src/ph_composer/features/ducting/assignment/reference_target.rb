# frozen_string_literal: true

module PhComposer
  module Ducting
    module Assignment
      # The duct reference target, over the shared line-group layer (LineGroups::EdgeTarget): the records provider the
      # engine's reference scan reads, so a Duct Type a duct names cannot be deleted unseen, and the resolver every
      # write goes through. A duct's reference names its Ducting group's path and the Edge's own root-to-Edge path.
      REFERENCE = {
        "type" => "object", "additionalProperties" => false, "required" => %w[group_path entity_path entity_id],
        "properties" => {
          "group_path" => LineGroups::PATH.merge("minItems" => 1, "description" => "The root-to-Group path of the " \
                                                                                   "Ducting group holding the Edge."),
          "entity_path" => LineGroups::PATH.merge("minItems" => 2, "description" => "The root-to-Edge path: " \
                                                                                    "group_path and the Edge's " \
                                                                                    "persistent id."),
          "entity_id" => { "type" => %w[string null],
                           "description" => "The Edge's assignment id, or null for an Edge with none." }
        }
      }.freeze

      TARGET = Records::ReferenceTarget.new(
        :id => DUCT_KIND, :label => "Duct", :schema_version => 1, :values => RECORD_KIND.values_schema,
        :occurrence => REFERENCE, :records => ->(model) { LineGroups::EdgeTarget.entries(LINE_GROUP, model) },
        :validate => ->(record) { RECORD_KIND.problems(record) }, :references => RECORD_KIND.references,
        :locate => lambda { |model, reference, mutable:, index: nil|
          LineGroups::EdgeTarget.locate(LINE_GROUP, model, reference, :mutable => mutable, :index => index)
        },
        :locate_index => ->(_model) { Zones::ChildLookup.new }
      )
    end
  end
end
