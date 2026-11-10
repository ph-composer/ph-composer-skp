# frozen_string_literal: true

module PhComposer
  module Windows
    # Adapter assignments call the operations the owning actions call, on the shared copy proposal.
    # Targets carry authored guards; changing a single side never replaces another element's
    # assignments.
    module LibraryAssignment
      module_function

      def target_schema(collection)
        target = { "id" => Shapes::TEXT, "element_id" => Shapes::TEXT,
                   "expected_values" => Types::KIND.descriptor.patch_schema }
        target["side"] = { "type" => "string", "enum" => Types::SIDES } unless collection == "glazings"
        return Shapes.object(target) unless collection == "psi_install_types"

        target.merge!("mode" => { "type" => "string", "enum" => %w[perimeter model_default] },
                      "expected_settings" => Settings::VALUES)
        Shapes.object(target, :optional => %w[id element_id expected_values side])
      end

      # One target per shape the collection's assignment takes: a Window Type element side for a Frame or
      # an install, the element for a Glazing, and the Model default for an install.
      def examples(collection)
        element = { "id" => GridRegistration::EXAMPLE_ID, "element_id" => GridRegistration::EXAMPLE_ELEMENT,
                    "expected_values" => {} }
        settings = Settings::DEFAULTS
        targets = case collection
                  when "glazings" then [element]
                  when "frames" then [element.merge("side" => "left")]
                  else [element.merge("side" => "bottom", "mode" => "perimeter", "expected_settings" => settings),
                        { "mode" => "model_default", "expected_settings" => settings }]
                  end
        ids = { "frames" => "frm_Ab12Cd34Ef56", "glazings" => "glz_Ab12Cd34Ef56" }
        local = ids.fetch(collection, "psi_Ab12Cd34Ef56")
        targets.map { |target| { "target" => target, "local_id" => local } }
      end

      def callback(collection)
        result = Shapes.object({ "assigned" => { "type" => "boolean" } })
        Declarations::LibraryCallback.new(
          :params => Shapes.object({ "target" => target_schema(collection), "local_id" => Shapes::TEXT }),
          :examples => examples(collection),
          :result => result, :refuses => collection == "psi_install_types" ? Refuses::EDIT : Refuses::TYPE_EDIT,
          :handler => lambda do |request, proposal|
            target = request.params.fetch("target")
            id = request.params.fetch("local_id")
            if collection == "psi_install_types"
              assign_psi(request, proposal, target, id)
            elsif collection == "frames"
              values = { "element_id" => target.fetch("element_id"), "side" => target.fetch("side"), "frame_id" => id }
              assign_grid(request, proposal, target, "set_element_frame", values) do |record|
                GridOperations.set_element_frame(record, values)
              end
            else
              values = { "element_id" => target.fetch("element_id"), "glazing_id" => id }
              assign_grid(request, proposal, target, "set_element_glazing", values) do |record|
                GridOperations.set_element_glazing(record, values)
              end
            end
            { "assigned" => true }
          end
        )
      end

      # The same grid gesture the action of that name makes, guarded by the target's expected values.
      def assign_grid(request, proposal, target, gesture, values, &change)
        Authoring.grid(request, proposal,
                       :gesture => gesture, :id => target.fetch("id"), :values => values,
                       :expected_values => target.fetch("expected_values")) do |record, _identity|
          change.call(record)
        end
      end

      def assign_psi(request, proposal, target, id)
        if target.fetch("mode") == "model_default"
          unless target.keys.sort == %w[expected_settings mode]
            raise CodedError.new("params.invalid", "A Model default target cannot contain element fields.")
          end

          values = Settings.read(request.model).merge("default_psi_install_id" => id)
          Authoring.update_settings(request, proposal, :values => values,
                                                       :expected_values => target.fetch("expected_settings"))
          return
        end
        unless target.keys.sort == %w[element_id expected_settings expected_values id mode side]
          raise CodedError.new("params.invalid", "A perimeter target needs a guarded element and side.")
        end

        record = request.engine.find(TYPE_KIND, target.fetch("id"))
        after = Installs.paint(record, target.fetch("element_id"), target.fetch("side"), id)
        element = after.fetch("elements").find { |cell| cell.fetch("id") == target.fetch("element_id") }
        edge = { "element_id" => element.fetch("id"), "sides" => element.fetch("installs") }
        InstallSave.call(request, proposal,
                         :types => [{ "id" => target.fetch("id"), "expected_values" => target.fetch("expected_values"),
                                      "installs" => [edge] }],
                         :psi_install_types => { "create" => [], "update" => [] },
                         :expected_settings => target.fetch("expected_settings"))
      end
    end
  end
end
