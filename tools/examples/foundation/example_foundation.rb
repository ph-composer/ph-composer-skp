# frozen_string_literal: true

# A complete, development-only feature built from the public contracts alone. It never ships: the RBZ
# builder refuses any `examples` path, and the shipping composition root does not list it. Load it
# with tools/examples/foundation/load.rb. The README beside this file walks through it.
#
# It declares two record kinds, two structured extensions (one stored on Zones' Faces), a query, four
# actions, a proposal participant, a snapshot section and three export contributors. Nothing in
# shell/, session/, core/ or export/ names it; its translation sections are in example_translation.py beside this file.
module ExampleFoundation
  ID = "example.foundation"
  DEFINITION = "#{ID}.definition"
  PART = "#{ID}.part"
  REVIEW = "#{ID}.review"
  FACE_REVIEW = "#{ID}.face_review"
  FACES_SECTION = "ph_composer.zones.faces.export.faces"
  FACE_KIND = "ph_composer.zones.faces.face"

  Records = PhComposer::Records

  # A shared definition that many parts name, like a construction many faces use.
  DEFINITION_KIND = Records::RecordKind.new(
    :id => DEFINITION, :label => "Example definition", :schema_version => 1, :id_prefix => "exd",
    :fields => [Records::Field.new(:key => "label", :required => true,
                                   :schema => { "type" => "string", "minLength" => 1 })]
  )

  # A part with a label, an SI length and a reference to its definition. Stored lengths are
  # millimetres; the key says so and so does the schema's `x-unit`.
  PART_KIND = Records::RecordKind.new(
    :id => PART, :label => "Example part", :schema_version => 1, :id_prefix => "exp",
    :fields => [
      Records::Field.new(:key => "label", :schema => { "type" => "string", "minLength" => 1 }, :required => true),
      Records::Field.new(:key => "length_mm", :required => true,
                         :schema => { "type" => "number", "exclusiveMinimum" => 0, "x-unit" => "mm" }),
      Records::Reference.new(:key => "definition_id", :target_kind => DEFINITION, :cardinality => "one",
                             :required => true)
    ]
  )

  # Structured review data on parts. Version 1 stored `{"status": ...}`; version 2 renamed the key
  # and may name the part it was checked against, which a duplicated collection remaps.
  REVIEW_EXTENSION = Records::Extension.new(
    :namespace => REVIEW, :schema_version => 2, :export_relevance => "required",
    :references => [{ "path" => "$.checked_against", "target_kind" => PART, "cardinality" => "one" }],
    :migrations => { 1 => ->(payload) { { "review_status" => payload.fetch("status") } } },
    :validate => lambda do |payload|
      %w[draft checked].include?(payload["review_status"]) ? [] : ["review_status must be draft or checked"]
    end
  )

  # A review stored on Zones' Faces, which this feature does not own. Zones exports Faces and names
  # no review; the face-review section below claims the payload and its translation writes it to the
  # HBJSON Face's user_data.
  FACE_REVIEW_EXTENSION = Records::Extension.new(
    :namespace => FACE_REVIEW, :schema_version => 1, :export_relevance => "required",
    :validate => lambda do |payload|
      %w[draft checked].include?(payload["review_status"]) ? [] : ["review_status must be draft or checked"]
    end
  )

  OBJECT = { "type" => "object" }.freeze
  IDS = { "type" => "array", "items" => { "type" => "string" }, "minItems" => 1 }.freeze
  PART_VALUES = {
    "type" => "object", "required" => %w[label length_mm], "additionalProperties" => false,
    "properties" => {
      "label" => { "type" => "string", "minLength" => 1 },
      "length_mm" => { "type" => "number", "exclusiveMinimum" => 0, "x-unit" => "mm" }
    }
  }.freeze
  EDIT = {
    "type" => "object", "required" => ["id"], "additionalProperties" => false,
    "properties" => {
      "id" => { "type" => "string", "description" => "The part to edit." },
      "values" => { "type" => "object", "description" => "Values to set; null removes an optional one." },
      "expected_values" => { "type" => "object", "description" => "The values last read; a change refuses." },
      "review" => { "type" => "object", "description" => "Sets the #{REVIEW} payload." }
    }
  }.freeze

  module_function

  # The one entrypoint. It only declares; the registry validates and publishes.
  def install(registry)
    feature = registry.feature(ID, :contract_version => 1, :requires => ["ph_composer.zones"])
    feature.record_kind(DEFINITION_KIND)
    feature.record_kind(PART_KIND)
    feature.extension(REVIEW_EXTENSION)
    feature.extension(FACE_REVIEW_EXTENSION)
    feature.snapshot_section("#{ID}.parts", :query => "ph_composer.records.list", :params => { "kind" => PART })
    declare_summary(feature)
    declare_create(feature)
    declare_update(feature)
    declare_duplicate_and_migrate(feature)
    declare_participant(feature)
    declare_export(feature)
  end

  ADD_PART = {
    "type" => "object", "required" => %w[definition_id label length_mm], "additionalProperties" => false,
    "properties" => PART_VALUES.fetch("properties").merge(
      "definition_id" => { "type" => "string", "description" => "The definition the new part names." }
    )
  }.freeze

  # A step another feature's action composes into its own proposal (example_kit.rb is the caller). It
  # stages one part; it cannot write another feature's kinds, and it opens no operation of its own.
  def declare_participant(feature)
    feature.proposal_participant(
      "#{ID}.add_part",
      :description => "Stage one part that names an existing definition, inside the caller's proposal.",
      :params => ADD_PART, :refuses => %w[reference.invalid validation.failed],
      :result => { "type" => "object", "required" => ["part_id"], "additionalProperties" => false,
                   "properties" => { "part_id" => { "type" => "string" } } },
      :examples => [{ "definition_id" => "exd_Ab12Cd34Ef56", "label" => "Jamb", "length_mm" => 2100 }]
    ) do |request, proposal|
      { "part_id" => request.engine.propose_create(PART, proposal, :values => request.params) }
    end
  end

  def declare_summary(feature)
    feature.query(
      "#{ID}.summary", :description => "Count and total length of every part.",
                       :refuses => %w[record.unreadable],
                       :params => { "type" => "object", "additionalProperties" => false },
                       :result => { "type" => "object", "properties" => {
                         "parts" => { "type" => "integer" }, "total_length_mm" => { "type" => "number",
                                                                                    "x-unit" => "mm" }
                       } }
    ) do |request|
      lengths = request.engine.ids(PART).map { |id| request.engine.find(PART, id).fetch("length_mm") }
      { "parts" => lengths.length, "total_length_mm" => lengths.sum }
    end
  end

  def declare_create(feature)
    feature.action(
      "#{ID}.create_parts",
      :description => "Create one definition and parts that name it.",
      :params => { "type" => "object", "required" => %w[definition_label parts],
                   "additionalProperties" => false,
                   "properties" => { "definition_label" => { "type" => "string", "minLength" => 1 },
                                     "parts" => { "type" => "array", "items" => PART_VALUES,
                                                  "minItems" => 1 } } },
      :result => OBJECT, :refuses => %w[reference.invalid validation.failed], :undo_name => "Create Example Parts",
      :side_effects => "Creates records.",
      :examples => [{ "definition_label" => "Frame", "parts" => [{ "label" => "Sill",
                                                                   "length_mm" => 1200 }] }]
    ) do |request, changes|
      engine = request.engine
      definition = engine.propose_create(DEFINITION, changes,
                                         :values => { "label" => request.params.fetch("definition_label") })
      parts = request.params.fetch("parts").map do |values|
        engine.propose_create(PART, changes, :values => values.merge("definition_id" => definition))
      end
      { "definition_id" => definition, "part_ids" => parts }
    end
  end

  # All edits succeed together or none is written.
  def declare_update(feature)
    feature.action(
      "#{ID}.update_parts", :description => "Edit parts' values or review, all or none.",
                            :params => { "type" => "object", "required" => ["edits"], "additionalProperties" => false,
                                         "properties" => { "edits" => { "type" => "array", "items" => EDIT,
                                                                        "minItems" => 1 } } },
                            :result => OBJECT, :undo_name => "Edit Example Parts",
                            :refuses => %w[extension.migration_required extension.schema_unsupported
                                           extension.unavailable record.unreadable reference.invalid target.changed
                                           target.not_found validation.failed],
                            :side_effects => "Changes part values and metadata.",
                            :examples => [{ "edits" => [{ "id" => "exp_Ab12Cd34Ef56",
                                                          "values" => { "length_mm" => 900 } }] }]
    ) do |request, changes|
      request.params.fetch("edits").each do |edit|
        request.engine.propose_update(
          PART, edit.fetch("id"), changes,
          :values => edit.fetch("values", {}), :expected_values => edit.fetch("expected_values", {}),
          :extension_payloads => edit.key?("review") ? { REVIEW => edit["review"] } : {}
        )
      end
      { "updated" => changes.affected.map { |row| row.fetch("id") } }
    end
  end

  def declare_duplicate_and_migrate(feature)
    feature.action(
      "#{ID}.duplicate_parts",
      :description => "Duplicate parts as one collection.",
      :params => { "type" => "object", "required" => ["ids"], "properties" => { "ids" => IDS } },
      :result => OBJECT, :undo_name => "Duplicate Example Parts",
      :refuses => %w[copy.rule_missing extension.invalid record.unreadable reference.invalid target.not_found
                     validation.failed],
      :side_effects => "Creates records.",
      :examples => [{ "ids" => ["exp_Ab12Cd34Ef56"] }]
    ) do |request, changes|
      { "mapping" => request.engine.propose_duplicate(PART, request.params.fetch("ids"), changes) }
    end

    feature.action(
      "#{ID}.migrate_review",
      :description => "Raise review data to the installed version.",
      :params => { "type" => "object", "required" => ["ids"], "properties" => { "ids" => IDS } },
      :result => OBJECT, :undo_name => "Migrate Example Review",
      :refuses => %w[extension.invalid extension.migration_failed extension.schema_unsupported record.unreadable
                     target.not_found validation.failed],
      :side_effects => "Rewrites extension data.",
      :examples => [{ "ids" => ["exp_Ab12Cd34Ef56"] }]
    ) do |request, changes|
      { "results" => request.engine.propose_migration(PART, request.params.fetch("ids"), REVIEW, changes) }
    end
  end

  # Definitions, then parts with their review status. Parts name their definition by durable id, which
  # the translation's parts section resolves through its requirement on definitions. User data never
  # leaves the Model; the reader says so in a finding.
  def declare_export(feature)
    feature.export_contributor("#{ID}.export.definitions", :section_version => 1) do |reader|
      reader.records(DEFINITION)
    end
    feature.export_contributor(
      "#{ID}.export.parts",
      :section_version => 1,
      :result => { "example_parts" => PhComposer::Export::Privacy.fields(%w[count
                                                                            total_length_mm]) },
      :report => method(:parts_report)
    ) { |reader| reader.records(PART, :extensions => { REVIEW => ["review_status"] }) }
    feature.export_contributor(
      "#{ID}.export.face_reviews", :section_version => 1, :requires => [FACES_SECTION],
                                   :user_data_keys => ["#{ID}.face_review"],
                                   :entity_projections => [{ "namespace" => FACE_REVIEW, "target_kind" => FACE_KIND,
                                                             "source_section" => FACES_SECTION,
                                                             "fields" => ["review_status"] }]
    ) do |reader|
      reader.entity_projection(FACE_REVIEW, FACE_KIND).map do |row|
        { "id" => row.fetch("id"), "review_status" => row.fetch("payload")["review_status"] }
      end
    end
  end

  def parts_report(result, display_units)
    parts = result.fetch("example_parts")
    length = PhComposer::Units.format(parts.fetch("total_length_mm"), :quantity => "length_mm",
                                                                      :system => display_units)
    html = PhComposer::Export::ReportHtml
    [html.section("Example parts", html.table(%w[Parts Total\ length], [[parts.fetch("count"), length]]))]
  end
end
