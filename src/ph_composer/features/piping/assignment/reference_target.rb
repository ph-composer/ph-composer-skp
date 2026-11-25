# frozen_string_literal: true

module PhComposer
  module Piping
    module Assignment
      # The pipe reference target, over the shared line-group layer (LineGroups::EdgeTarget): the records provider
      # the engine's reference scan reads, so a Pipe Type a pipe names cannot be deleted unseen, and the resolver every
      # write goes through. A pipe's reference names its Piping group's path and the Edge's own root-to-Edge path.
      module Target
        PATH = Group::Target::PATH
        REFERENCE = {
          "type" => "object", "additionalProperties" => false, "required" => %w[group_path entity_path entity_id],
          "properties" => {
            "group_path" => PATH.merge("minItems" => 1, "description" => "The root-to-Group path of the Piping " \
                                                                         "group holding the Edge."),
            "entity_path" => PATH.merge("minItems" => 2, "description" => "The root-to-Edge path: group_path and " \
                                                                          "the Edge's persistent id."),
            "entity_id" => { "type" => %w[string null],
                             "description" => "The Edge's assignment id, or null for an Edge with none." }
          }
        }.freeze

        module_function

        def entries(model)
          LineGroups::EdgeTarget.entries(LINE_GROUP, model)
        end

        def locate(model, reference, mutable:, index: nil)
          LineGroups::EdgeTarget.locate(LINE_GROUP, model, reference, :mutable => mutable, :index => index)
        end
      end

      TARGET = Records::ReferenceTarget.new(
        :id => PIPE_KIND, :label => "Pipe", :schema_version => 1, :values => RECORD_KIND.values_schema,
        :occurrence => Target::REFERENCE, :records => Target.method(:entries),
        :validate => ->(record) { RECORD_KIND.problems(record) }, :references => RECORD_KIND.references,
        :locate => Target.method(:locate), :locate_index => ->(_model) { Zones::ChildLookup.new }
      )
    end
  end
end
