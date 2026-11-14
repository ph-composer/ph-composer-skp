# frozen_string_literal: true

require_relative "record_queries"

module PhComposer
  # The Model's own metadata: one `user_data` map and one `extension_data` map for the building as a whole,
  # under the Records::Metadata rules every record follows (context/CONTRACTS.md, "Model settings"). It lives
  # in its own ModelSettings dictionary, so it is never confused with a feature's settings, and it is
  # registered by the foundation, as the record reads are, because the Model belongs to no feature.
  module ModelMetadata
    FEATURE_ID = "ph_composer.model"
    DETAIL = "#{FEATURE_ID}.detail"
    FRAGMENT = "#{FEATURE_ID}.fragment"
    # The parts of the detail answer FRAGMENT reaches.
    PARTS = %w[user_data extension_data extension_status].freeze
    UPDATE_METADATA = "#{FEATURE_ID}.update_metadata"
    # The export section that carries the Model's user_data to the Honeybee Model's own user_data
    # (python/ph_composer_translation/model_metadata.py), and its preflight.
    SECTION = "#{FEATURE_ID}.export.model"
    PREFLIGHT = "#{FEATURE_ID}.export_preflight"
    # What the Records::Metadata messages call the Model in place of a record id, after LABEL in place of a
    # kind's label: "The Model metadata changed since it was read.", "... data on Model ...".
    TARGET_ID = "Model"
    LABEL = "The"
    # The reference target that puts the Model's envelopes in the engine's incoming-reference inventory, so a
    # record a Model payload names refuses deletion as reference.in_use, as it would from any record's payload.
    REFERENCE_KIND = "#{FEATURE_ID}.metadata"
    MAP = { "type" => "object" }.freeze
    MAPS = SchemaShapes.object({ "user_data" => MAP, "extension_data" => MAP }).freeze
    SETTINGS = ModelSettings.new(:dictionary => "ph_composer.model",
                                 :defaults => { "user_data" => {}, "extension_data" => {} }, :schema => MAPS,
                                 :label => "Model metadata", :step_name => "update_model_metadata",
                                 :affected => [{ "kind" => "model_metadata", "id" => FEATURE_ID,
                                                 "change" => "updated" }]) do |values|
      values.flat_map { |key, map| JsonValue.problems(map).map { |problem| "#{key} #{problem}" } }
    end

    STATUS = { "type" => "object", "description" => "Each extension envelope's status against what is installed." }
             .freeze
    DETAIL_PARAMS = SchemaShapes.object({
      "metadata" => { "type" => "string", "enum" => %w[full summary],
                      "description" => "full (the default): user_data, extension_data and extension_status as " \
                                       "stored. summary: none of them, but their sizes, digests and status counts in " \
                                       "metadata; read any of them whole with #{FRAGMENT}." }
    }, :optional => ["metadata"]).freeze
    DETAIL_RESULT = SchemaShapes.object({
      "user_data" => SchemaShapes.described(MAP, "Contributor metadata, preserved as written; {} when none."),
      "extension_data" => SchemaShapes.described(MAP, "Versioned payloads registered extensions own."),
      "extension_status" => STATUS,
      "metadata" => RecordQueries::METADATA
    }, :optional => %w[user_data extension_data extension_status metadata],
       :description => "The three maps, or with metadata summary what they hold in metadata.").freeze
    FRAGMENT_PARAMS = SchemaShapes.object({
      "path" => Fragments.path_param(PARTS, "[\"user_data\"], [\"user_data\", \"notes\"]"),
      "cursor" => Pages::CURSOR
    }, :optional => ["cursor"]).freeze
    FRAGMENT_RESULT = SchemaShapes.object({ "type" => Fragments::TYPE, "fragment" => Fragments::FRAGMENT,
                                            "next_cursor" => Pages::NEXT_CURSOR }).freeze
    # A write answers the statuses only, so a map of any size never makes its own reply too large; read the
    # maps back with DETAIL or FRAGMENT.
    RESULT = SchemaShapes.object({ "extension_status" => STATUS }).freeze
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
                                            "status. A Model that never had any reads both as {}, without a write. " \
                                            "With metadata summary, only their sizes, for maps larger than a reply.",
                            :refuses => %w[record.unreadable], :params => DETAIL_PARAMS, :result => DETAIL_RESULT,
                            :examples => [{}, { "metadata" => "summary" }]) do |request|
        view = detail(request.model, request.registry.catalog)
        request.params["metadata"] == "summary" ? RecordQueries.summarize(view, {}).slice("metadata") : view
      end
      feature.query(FRAGMENT, :description => "One part of #{DETAIL}'s answer, exactly, as canonical JSON text in " \
                                              "fragments: join every fragment's text in order, check its sha256 and " \
                                              "parse it. Pass next_cursor back for the next fragment.",
                              :refuses => %w[query.cursor_expired record.unreadable target.not_found],
                              :params => FRAGMENT_PARAMS, :result => FRAGMENT_RESULT,
                              :examples => [{ "path" => ["user_data"] }]) do |request|
        Fragments.detail(request, FRAGMENT, detail(request.model, request.registry.catalog),
                         request.params.fetch("path"), :parts => PARTS)
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
      feature.reference_target(Records::ReferenceTarget.new(
        :id => REFERENCE_KIND, :label => "Model metadata", :records => method(:reference_entries),
        # SETTINGS.read refuses unreadable maps before an entry exists, so an entry has nothing left to find.
        :validate => ->(_record) { [] }
      ))
      feature.export_contributor(SECTION, :section_version => 1, :preflight => PREFLIGHT) do |reader|
        export_records(reader)
      end
      feature.query(PREFLIGHT, :description => "Whether the Model's own metadata can be exported.",
                               :refuses => [], :params => SchemaShapes.object({}), :result => Export::PREFLIGHT_RESULT,
                               :examples => [{}]) { |request| export_preflight(request) }
    end

    # The Model's maps as the one occurrence of REFERENCE_KIND, by TARGET_ID.
    def reference_entries(model)
      [Records::ReferenceEntry.new(:kind => REFERENCE_KIND, :key => TARGET_ID,
                                   :record => SETTINGS.read(model).merge("id" => TARGET_ID))]
    end

    # The Model's user_data leaves on the Honeybee Model as one record, read from the export snapshot through the
    # boundary every record passes: the reserved-key rule for its map and the left-out rules for its envelopes.
    # A Model with no user_data leaves no record.
    def export_records(reader)
      maps = snapshot_maps(reader.snapshot).merge("id" => TARGET_ID)
      exported = reader.entity_record(maps, :fields => [], :user_data => true)
      exported.key?("user_data") ? [exported] : []
    end

    def snapshot_maps(snapshot)
      text = snapshot.model_dictionaries.fetch(SETTINGS.store.dictionary, {})[SETTINGS.store.key]
      SETTINGS.validate!(SETTINGS.effective(text.nil? ? nil : JSON.parse(text)))
    rescue JSON::ParserError, CodedError
      raise Export::Blocked.new("record.unreadable", "The Model metadata cannot be read, so it cannot be exported. " \
                                                     "Nothing was written.")
    end

    # What `export_records` would refuse, as blocking rows.
    def export_preflight(request)
      maps = SETTINGS.read(request.model).merge("id" => TARGET_ID)
      { "findings" => Export::MetadataCheck.findings(request, [maps], :section => SECTION, :user_data => true),
        "repairs" => [] }
    rescue CodedError => error
      { "findings" => [{ "code" => error.code, "section" => SECTION, "object_id" => TARGET_ID,
                         "message" => error.message, "blocks_export" => true }], "repairs" => [] }
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
      { "extension_status" => Records::Metadata.status_map(after, catalog) }
    end
  end
end
