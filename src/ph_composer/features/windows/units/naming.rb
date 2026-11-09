# frozen_string_literal: true

require_relative "occurrences"
require_relative "mutation_scope"

module PhComposer
  module Windows
    module Units
      # Sets one occurrence's instance name, resolved again and checked against the name it was planned
      # from. The name is not in the Unit record, so the step guards it itself.
      class RenameStep
        attr_reader :reference, :before, :after, :affected

        def initialize(reference:, before:, after:)
          @reference = DeepCopy.call(reference).freeze
          @before = before.dup.freeze
          @after = after.dup.freeze
          @affected = [{ "kind" => REFERENCE_KIND, "id" => @reference.fetch("unit_id"), "change" => "updated",
                         "reference" => @reference }].freeze
        end

        def descriptor
          { "name" => "rename_window_unit", "reference" => DeepCopy.call(reference), "before" => before,
            "after" => after }
        end

        def apply(model, _slots)
          item = Occurrences.resolve(model, reference, :mutable => true)
          raise CodedError.new("target.changed", "A Window's name changed after it was previewed.") \
            unless item.entity.name == before

          item.entity.name = after
        end
      end

      # A Unit's name is its native instance name, the field Entity Info calls Instance. Nothing stores a
      # second copy, so the Schedule and Entity Info edit one value. An empty name is a Unit with no name.
      module Naming
        module_function

        def rename(request, proposal, unit:, name:, expected_name:)
          item = Occurrences.resolve(request.model, unit, :mutable => true)
          unless item.entity.name == expected_name
            raise CodedError.new("target.changed", "This Window's name changed in the Model. Nothing was written.")
          end

          reference = item.reference.merge("unit_id" => Mutation.record(proposal, item).fetch("id"))
          unless name == expected_name
            proposal.add_step(RenameStep.new(:reference => reference, :before => expected_name, :after => name),
                              :scopes => [MutationScope.new])
          end
          { "unit_id" => reference.fetch("unit_id"), "name" => name }
        end

        # The Window occurrences in SketchUp's selection, at the active edit path. A selected container
        # holding Windows is not a selected Window.
        def selected(model)
          parent = Array(model.active_path).map(&:persistent_id)
          model.selection.to_a.filter_map do |entity|
            record = unit_record(entity)
            { "unit_id" => record.fetch("id"), "entity_path" => parent + [entity.persistent_id] } if record
          end
        end

        def unit_record(entity)
          Units.read(entity) if entity.is_a?(Sketchup::ComponentInstance)
        rescue CodedError
          nil # An unreadable record is the Unit read's to report.
        end
        private_class_method :unit_record
      end
    end
  end
end
