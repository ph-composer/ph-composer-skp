# frozen_string_literal: true

module PhComposer
  # The Model's own metadata: one `user_data` map and one `extension_data` map for the building as a whole,
  # under the Records::Metadata rules every record follows (context/CONTRACTS.md, "Model settings"). It lives
  # in its own ModelSettings dictionary, so it is never confused with a feature's settings, and it is
  # registered by the foundation, as the record reads are, because the Model belongs to no feature.
  module ModelMetadata
    FEATURE_ID = "ph_composer.model"
    DETAIL = "#{FEATURE_ID}.detail"
    UPDATE_METADATA = "#{FEATURE_ID}.update_metadata"
    # What the Records::Metadata messages call the Model in place of a record id, after LABEL in place of a
    # kind's label: "The Model metadata changed since it was read.", "... data on Model ...".
    TARGET_ID = "Model"
    LABEL = "The"
    MAP = { "type" => "object" }.freeze
    MAPS = SchemaShapes.object({ "user_data" => MAP, "extension_data" => MAP }).freeze
    SETTINGS = ModelSettings.new(:dictionary => "ph_composer.model",
                                 :defaults => { "user_data" => {}, "extension_data" => {} }, :schema => MAPS,
                                 :label => "Model metadata", :step_name => "update_model_metadata",
                                 :affected => [{ "kind" => "model_metadata", "id" => FEATURE_ID,
                                                 "change" => "updated" }]) do |values|
      values.flat_map { |key, map| JsonValue.problems(map).map { |problem| "#{key} #{problem}" } }
    end

    RESULT = SchemaShapes.object({
      "user_data" => SchemaShapes.described(MAP, "Contributor metadata, preserved as written; {} when none."),
      "extension_data" => SchemaShapes.described(MAP, "Versioned payloads registered extensions own."),
      "extension_status" => { "type" => "object",
                              "description" => "Each extension envelope's status against what is installed." }
    }).freeze
    PARAMS = SchemaShapes.object({
      "user_data" => { "type" => "object", "description" => "Replaces the whole user_data map; {} clears it." },
      "extension_payloads" => { "type" => "object", "additionalProperties" => { "type" => "object" },
                                "description" => "Replaces the payload of each named installed extension." },
      "expected_metadata" => SchemaShapes.described(MAPS, "The user_data and extension_data last read; a change " \
                                                          "refuses.")
    }, :optional => %w[user_data extension_payloads]).freeze
    UPDATE_REFUSES = %w[extension.invalid extension.migration_required extension.schema_unsupported
                        extension.unavailable record.unreadable reference.invalid target.changed
                        validation.failed].freeze

    module_function

    def install(registry)
      feature = registry.feature(FEATURE_ID, :contract_version => Declarations::CONTRACT_VERSION)
      feature.query(DETAIL, :description => "The Model's own user_data and extension_data, with each envelope's " \
                                            "status. A Model that never had any reads both as {}, without a write.",
                            :refuses => %w[record.unreadable], :params => SchemaShapes.object({}), :result => RESULT,
                            :examples => [{}]) do |request|
        detail(request.model, request.registry.catalog)
      end
      feature.action(UPDATE_METADATA,
                     :description => "Replace the Model's own user_data, installed extension payloads or both, " \
                                     "guarded by the metadata last read, in one Undo step; writing what is stored " \
                                     "adds none. Feature settings are not touched.",
                     :refuses => UPDATE_REFUSES, :params => PARAMS, :result => RESULT,
                     :undo_name => "Edit Model Metadata",
                     :examples => [{ "user_data" => { "example_org" => { "project_number" => "2611" } },
                                     "expected_metadata" => { "user_data" => {}, "extension_data" => {} } }],
                     :side_effects => "Stores the maps in this SKP.") do |request, proposal|
        update_metadata(request, proposal, request.params)
      end
    end

    def detail(model, catalog)
      maps = SETTINGS.read(model)
      maps.merge("extension_status" => Records::Metadata.status_map(maps, catalog))
    end

    # The maps as stored, read as one record would be, planned under its pre-image and payload rules, then
    # staged as the settings step, which adds nothing when they are unchanged.
    def update_metadata(request, proposal, params)
      unless params.key?("user_data") || params.key?("extension_payloads")
        raise CodedError.new("params.invalid", "An update names user_data, extension_payloads or both.")
      end

      catalog = request.registry.catalog
      before = SETTINGS.read(request.model)
      planned = Records::Metadata.planned(request.engine, catalog, before.merge("id" => TARGET_ID), params, LABEL)
      after = SETTINGS.propose(request.model, proposal, :values => planned.slice("user_data", "extension_data"),
                                                        :expected_values => before)
      after.merge("extension_status" => Records::Metadata.status_map(after, catalog))
    end
  end
end
