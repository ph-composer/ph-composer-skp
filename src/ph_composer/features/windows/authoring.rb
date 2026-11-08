# frozen_string_literal: true

module PhComposer
  module Windows
    # Every Windows command that changes a definition runs through here, in one order: the
    # copied-identity repair the feature advertises on every action (Units::Mutation.prepare), the
    # definition's own record proposal, then what the placed Units must do to follow it. Product and
    # Type operations below it know only records; Units know only Units; this module knows both and
    # nothing else does. A compound command that is its own coordinator (InstallSave) prepares once
    # and calls the operations directly.
    module Authoring
      module_function

      def create_product(request, proposal, collection, values:, user_data: nil)
        Units::Mutation.prepare(request, proposal)
        Products::Operations.create(request, proposal, collection, :values => values, :user_data => user_data)
      end

      def update_product(request, proposal, collection, id:, values:, expected_values:, user_data: nil)
        Units::Mutation.prepare(request, proposal)
        Products::Operations.update(request, proposal, collection, :id => id, :values => values,
                                                                   :expected_values => expected_values,
                                                                   :user_data => user_data)
      end

      def duplicate_product(request, proposal, collection, id:, name: nil, copy_datasheets: false)
        Units::Mutation.prepare(request, proposal)
        Products::Operations.duplicate(request, proposal, collection, :id => id, :name => name,
                                                                      :copy_datasheets => copy_datasheets)
      end

      def delete_product(request, proposal, collection, id:, expected_values: {}, retarget: false,
                         replacement_id: nil)
        Units::Mutation.prepare(request, proposal)
        Products::Operations.delete(request, proposal, collection, :id => id, :expected_values => expected_values,
                                                                   :retarget => retarget,
                                                                   :replacement_id => replacement_id)
      end

      def create_type(request, proposal, values:, user_data: nil)
        Units::Mutation.prepare(request, proposal)
        Types::Operations.create(request, proposal, :values => values, :user_data => user_data)
      end

      def update_type(request, proposal, id:, values:, expected_values:, user_data: nil)
        Units::Mutation.prepare(request, proposal)
        before = request.engine.find(TYPE_KIND, id)
        Types::Operations.update(request, proposal, :id => id, :values => values,
                                                    :expected_values => expected_values, :user_data => user_data)
        follow_type(request, proposal, before)
      end

      def duplicate_type(request, proposal, id:, name: nil, copy_datasheets: false)
        Units::Mutation.prepare(request, proposal)
        Types::Operations.duplicate(request, proposal, :id => id, :name => name, :copy_datasheets => copy_datasheets)
      end

      # Without `retarget`, the Type's own Windows go with it.
      def delete_type(request, proposal, id:, expected_values: {}, retarget: false, replacement_id: nil)
        Units::Mutation.prepare(request, proposal)
        current = request.engine.find(TYPE_KIND, id)
        result = Types::Operations.delete(request, proposal, :id => id, :expected_values => expected_values,
                                                             :retarget => retarget, :replacement_id => replacement_id)
        Units::TypeRetargeter.cleanup(request, proposal, current) unless retarget
        result
      end

      def grid(request, proposal, gesture:, id:, values:, expected_values:, &change)
        Units::Mutation.prepare(request, proposal)
        before = request.engine.find(TYPE_KIND, id)
        Types::Operations.grid(request, proposal, :gesture => gesture, :id => id, :values => values,
                                                  :expected_values => expected_values, &change)
        follow_type(request, proposal, before)
      end

      def update_settings(request, proposal, values:, expected_values:)
        Units::Mutation.prepare(request, proposal)
        Settings.propose(request, proposal, :values => values, :expected_values => expected_values)
      end

      def update_unit_metadata(request, proposal, updates:)
        Units::Mutation.prepare(request, proposal)
        Units::Metadata.update(request, proposal, :updates => updates)
      end

      def rename_unit(request, proposal, unit:, name:, expected_name:)
        Units::Mutation.prepare(request, proposal)
        Units::Naming.rename(request, proposal, :unit => unit, :name => name, :expected_name => expected_name)
      end

      # The placed Windows follow the Type as the proposal leaves it.
      def follow_type(request, proposal, before)
        id = before.fetch("id")
        after = proposal.find(TYPE_KIND, id)&.after || before
        Units::Changes.type(request, proposal, :before => before, :after => after)
        { "id" => id, "unit_count" => Units::Changes.count(request.model, id) }
      end
    end
  end
end
