# frozen_string_literal: true

require_relative "record_fixtures"

# A feature built only from the public registration calls, for the dispatch and API tests. It is the
# offline counterpart of the development example under tools/examples/foundation/.
module TestFeature
  ID = "test.fixture"
  R = PhComposer::Records
  OBJECT = { "type" => "object" }.freeze

  EDIT = {
    "type" => "object", "required" => ["id"], "additionalProperties" => false,
    "properties" => {
      "id" => { "type" => "string" },
      "values" => { "type" => "object" },
      "expected_values" => { "type" => "object" },
      "extension_payloads" => { "type" => "object" }
    }
  }.freeze
  EDITS = { "type" => "array", "items" => EDIT, "minItems" => 1 }.freeze

  module_function

  def install(registry)
    feature = registry.feature(ID, :contract_version => 1)
    feature.record_kind(RecordFixtures::DEFINITION)
    feature.record_kind(RecordFixtures::PART)
    feature.extension(RecordFixtures::REVIEW)
    feature.snapshot_section("#{ID}.parts", :query => "ph_composer.records.list", :params => { "kind" => "#{ID}.part" })
    declare_reads(feature)
    declare_reads_that_move_the_view(feature)
    declare_writes(feature)
    declare_record_operations(feature)
  end

  def declare_reads(feature)
    feature.query("#{ID}.total_length", :description => "Total part length.", :params => { "type" => "object" },
                                        :result => OBJECT, :refuses => []) do |request|
      engine = request.engine
      lengths = engine.ids("#{ID}.part").map { |id| engine.find("#{ID}.part", id).fetch("length_mm") }
      { "total_length_mm" => lengths.sum }
    end
  end

  # A view command: it changes what the host shows (here, the selection) and never a record.
  def declare_reads_that_move_the_view(feature)
    feature.view_command("#{ID}.look", :description => "Select every part's entity.",
                                       :params => { "type" => "object", "required" => ["count"],
                                                    "additionalProperties" => false,
                                                    "properties" => { "count" => { "type" => "integer" } } },
                                       :result => OBJECT, :examples => [{ "count" => 1 }],
                                       :refuses => %w[validation.failed]) do |request|
      raise PhComposer::UserError, "There is nothing to look at." if request.params.fetch("count").zero?

      request.model.selection.clear
      # A negative count changes the view and then fails, which is what a half-moved viewport looks like.
      raise "the camera could not be placed" if request.params.fetch("count").negative?

      { "selected" => request.params.fetch("count") }
    end
  end

  def declare_writes(feature)
    feature.action("#{ID}.create", :description => "Create a definition and parts that name it.",
                                   :params => { "type" => "object", "required" => ["parts"],
                                                "properties" => { "parts" => { "type" => "array" } } },
                                   :result => OBJECT, :refuses => [], :undo_name => "Create Test Parts",
                                   :examples => [{ "parts" => [{ "label" => "Sill", "length_mm" => 1200.0 }] }],
                                   :side_effects => "Creates records.") do |request, changes|
      definition = request.engine.propose_create("#{ID}.definition", changes, :values => { "label" => "Frame" })
      ids = request.params.fetch("parts").map do |values|
        request.engine.propose_create("#{ID}.part", changes, :values => values.merge("definition_id" => definition))
      end
      { "definition_id" => definition, "part_ids" => ids }
    end

    feature.action("#{ID}.update_parts", :description => "Edit parts, all or none.",
                                         :params => { "type" => "object", "required" => ["edits"],
                                                      "properties" => { "edits" => EDITS } },
                                         :result => OBJECT, :refuses => %w[validation.failed],
                                         :undo_name => "Edit Test Parts",
                                         :examples => [{ "edits" => [{ "id" => "tpt_Ab12Cd34Ef56" }] }],
                                         :side_effects => "Changes part values and metadata.") do |request, changes|
      request.params.fetch("edits").each do |edit|
        request.engine.propose_update(
          "#{ID}.part", edit.fetch("id"), changes,
          :values => edit.fetch("values", {}),
          :expected_values => edit.fetch("expected_values", {}),
          :extension_payloads => edit.fetch("extension_payloads", {})
        )
      end
      { "updated" => changes.affected.length }
    end
  end

  def declare_record_operations(feature)
    feature.action("#{ID}.duplicate_parts", :description => "Duplicate parts as one collection.",
                                            :params => { "type" => "object", "required" => ["ids"],
                                                         "properties" => { "ids" => { "type" => "array" } } },
                                            :result => OBJECT, :refuses => [], :undo_name => "Duplicate Test Parts",
                                            :examples => [{ "ids" => ["tpt_Ab12Cd34Ef56"] }],
                                            :side_effects => "Creates records.") do |request, changes|
      { "mapping" => request.engine.propose_duplicate("#{ID}.part", request.params.fetch("ids"), changes) }
    end

    feature.action("#{ID}.migrate_review", :description => "Raise review data to the installed version.",
                                           :params => { "type" => "object", "required" => ["ids"],
                                                        "properties" => { "ids" => { "type" => "array" } } },
                                           :result => OBJECT, :refuses => [], :undo_name => "Migrate Test Review",
                                           :examples => [{ "ids" => ["tpt_Ab12Cd34Ef56"] }],
                                           :side_effects => "Rewrites extension data.") do |request, changes|
      ids = request.params.fetch("ids")
      { "results" => request.engine.propose_migration("#{ID}.part", ids, "#{ID}.review", changes) }
    end

    # Rescues a refusal and returns as if it had succeeded, as a careless handler might.
    feature.action("#{ID}.swallow_refusal", :description => "Migrate, ignoring refusals.",
                                            :params => { "type" => "object", "required" => ["ids"],
                                                         "properties" => { "ids" => { "type" => "array" } } },
                                            :result => OBJECT, :refuses => %w[extension.migration_failed],
                                            :undo_name => "Swallow",
                                            :examples => [{ "ids" => ["tpt_Ab12Cd34Ef56"] }],
                                            :side_effects => "Rewrites extension data.") do |request, changes|
      begin
        request.engine.propose_migration("#{ID}.part", request.params.fetch("ids"), "#{ID}.review", changes)
      rescue PhComposer::CodedError
        nil
      end
      {}
    end

    # Calls the API again while its own request is still running, as a re-entrant client would.
    feature.action("#{ID}.reenter", :description => "Re-enter the dispatcher.", :params => { "type" => "object" },
                                    :result => OBJECT, :refuses => [], :undo_name => "Re-enter",
                                    :side_effects => "None.") do |_request, _changes|
      { "inner" => PhComposer::API.invoke(**TestFeature.reentry) }
    end
  end

  class << self
    attr_accessor :reentry
  end
end
