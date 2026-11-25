# frozen_string_literal: true

module PhComposer
  module Piping
    module Group
      # The Piping group reference target, over the shared line-group layer (LineGroups::GroupTarget): a reference
      # names the Group by its root-to-Group persistent-id path and its `ppg_` id.
      module Target
        PATH = LineGroups::PATH
        REFERENCE = {
          "type" => "object", "additionalProperties" => false, "required" => %w[group_id group_path],
          "properties" => {
            "group_id" => { "type" => "string", "description" => "The Piping group's ppg_ id." },
            "group_path" => PATH.merge("minItems" => 1,
                                       "description" => "The root-to-Group persistent-id path, one per placement.")
          }
        }.freeze

        module_function

        def entries(model)
          LineGroups::GroupTarget.entries(LINE_GROUP, model)
        end

        def each_group(model, &block)
          LineGroups::GroupTarget.each_group(LINE_GROUP, model, &block)
        end

        def write_refusal(containers)
          LineGroups::GroupTarget.write_refusal(LINE_GROUP, containers)
        end

        # Inside another Piping group. Inside a Zone is Zones' to say (ph_composer.zones.containment).
        def nested_refusal(above)
          LineGroups::GroupTarget.nested_refusal(LINE_GROUP, above)
        end

        def locate(model, reference, mutable:, index: nil)
          LineGroups::GroupTarget.locate(LINE_GROUP, model, reference, :mutable => mutable, :index => index)
        end
      end

      TARGET = Records::ReferenceTarget.new(
        :id => GROUP_KIND, :label => "Piping group", :schema_version => 1, :values => RECORD_KIND.values_schema,
        :occurrence => Target::REFERENCE, :records => Target.method(:entries),
        :validate => ->(record) { RECORD_KIND.problems(record) }, :references => RECORD_KIND.references,
        :locate => Target.method(:locate), :locate_index => ->(_model) { Zones::ChildLookup.new }
      )
    end
  end
end
