# frozen_string_literal: true

require_relative "../../core/model_settings"

module PhComposer
  module Windows
    # SKP-owned installation defaults, using the same guarded Model dictionary service as other features.
    # An edge with no Psi-Install Type inherits the default Type when one is chosen, and otherwise the Model's
    # own value. That value is a setting, not a shipped record, so no library provider is privileged.
    module Settings
      KIND = "#{FEATURE_ID}.settings_record"
      DEFAULT_VALUE_NAME = "Model default"
      DEFAULTS = { "default_psi_install_id" => nil, "default_psi_install_w_mk" => 0.04,
                   "default_install_depth_m" => 0.0 }.freeze
      VALUES = SchemaShapes.object({ "default_psi_install_id" => { "type" => %w[string null] },
                                     "default_psi_install_w_mk" => { "type" => "number", "x-unit" => "W/mK" },
                                     "default_install_depth_m" => { "type" => "number", "minimum" => 0,
                                                                    "x-unit" => "m" } }).freeze
      SERVICE = ModelSettings.new(:dictionary => "ph_composer.windows_settings", :defaults => DEFAULTS,
                                  :schema => VALUES, :label => "Window", :step_name => "update_window_settings",
                                  :affected => [{ "kind" => "window_settings", "id" => FEATURE_ID,
                                                  "change" => "updated" }])
      SLOT_ID = "wst_ModelDefaults"
      KEY = "ph_composer.windows_settings"

      module_function

      def read(model)
        SERVICE.read(model)
      end

      def entry(values)
        Records::ReferenceEntry.new(:kind => KIND, :key => KEY, :record => values.merge("id" => SLOT_ID))
      end

      TARGET = Records::ReferenceTarget.new(
        :id => KIND, :label => "Window defaults", :schema_version => 1, :values => VALUES,
        :records => ->(model) { [entry(read(model))] },
        :validate => ->(record) {
          (record["id"] == SLOT_ID ? [] : ["The Model settings identity is invalid."]) +
            JsonSchema.validate(record.reject { |key, _| key == "id" }, VALUES)
        },
        :references => [Records::Reference.new(:key => "default_psi_install_id", :target_kind => PSI_INSTALL_KIND,
                                               :cardinality => "one")]
      )

      # A record proposal only; the action and library assignment reach it through Windows::Authoring,
      # which runs the copied-identity repair first. `retarget` runs inside an already prepared delete.
      def propose(request, proposal, values:, expected_values:)
        if values["default_psi_install_id"]
          request.engine.find(PSI_INSTALL_KIND, values.fetch("default_psi_install_id"))
        end
        SERVICE.propose(request.model, proposal, :values => values, :expected_values => expected_values)
      end

      def retarget(request, proposal, from:, to:)
        before = read(request.model)
        return Records::ReferencePlan.new(:entries => []) unless before["default_psi_install_id"] == from

        after = before.merge("default_psi_install_id" => to)
        propose(request, proposal, :values => after, :expected_values => before)
        Records::ReferencePlan.new(:entries => [entry(after)])
      end

      def install(feature)
        feature.reference_target(TARGET)
        feature.reference_retargeter("#{FEATURE_ID}.settings.retarget_psi",
                                     :target_kind => PSI_INSTALL_KIND) do |request, proposal, from:, to:|
          retarget(request, proposal, :from => from, :to => to)
        end
        feature.query("#{FEATURE_ID}.settings.get",
                      :description => "The Model's installation defaults.",
                      :refuses => %w[record.unreadable],
                      :params => Shapes::NONE, :result => VALUES, :examples => [{}]) { |request| read(request.model) }
        feature.snapshot_section("#{FEATURE_ID}.settings", :query => "#{FEATURE_ID}.settings.get")
        feature.action("#{FEATURE_ID}.settings.update",
                       :description => "Set guarded installation defaults.",
                       :refuses => Refuses::EDIT,
                       :params => Shapes.object({ "values" => Shapes.described(VALUES, "The complete new defaults."),
                                                  "expected_values" => Shapes.described(
                                                    VALUES, "The defaults last read; a change refuses."
                                                  ) }),
                       :result => VALUES,
                       :undo_name => "Change Window Defaults",
                       :side_effects => Shapes.side_effects("Stores installation defaults in this SKP."),
                       :examples => [{ "values" => DEFAULTS,
                                       "expected_values" => DEFAULTS }]) do |request, proposal|
          Authoring.update_settings(request, proposal, :values => request.params.fetch("values"),
                                                       :expected_values => request.params.fetch("expected_values"))
        end
      end
    end
  end
end
