# frozen_string_literal: true

module PhComposer
  # The JSON Schema pieces every declaration builds params and results from. A feature's own
  # `Shapes` module extends this one and adds only the constants that are its own.
  module SchemaShapes
    # `extend self`, not `module_function`, so a feature module that extends this one gets public
    # methods.
    extend self

    # A colour as six-digit hex, `#a1b2c3`. A stored value reaches the panel's style attributes, so the
    # pattern is what keeps anything else out of them.
    HEX_COLOUR = { "type" => "string", "pattern" => "^#[0-9A-Fa-f]{6}$" }.freeze
    # The optional map a record kind's part (Records::Part) carries; absent reads as empty.
    PART_USER_DATA = { "type" => "object",
                       "description" => "Local JSON metadata of this part, written with " \
                                        "ph_composer.records.update_metadata by part_ids. A new part has none." }
                     .freeze
    # Whether a discard report (Records::Metadata.discard_report) left a removed map or a key out.
    DISCARD_TRUNCATED = { "type" => "boolean",
                          "description" => "True when removed_user_data leaves out a removed map or one of a " \
                                           "listed map's keys, by its count or byte limit." }.freeze

    # A closed object; every property is required unless `optional` names it.
    def object(properties, optional: [], description: nil)
      schema = { "type" => "object", "additionalProperties" => false,
                 "required" => properties.keys - optional, "properties" => properties }
      description ? described(schema, description) : schema
    end

    def list(items, description: nil)
      schema = { "type" => "array", "items" => items }
      description ? described(schema, description) : schema
    end

    # `base`, a closed object schema, with more required properties.
    def with(base, properties)
      base.merge("required" => base.fetch("required", []) + properties.keys,
                 "properties" => base.fetch("properties").merge(properties))
    end

    # `result` with what a merge or delete reports of the maps it removes (Records::Metadata.removed_user_data).
    def with_removed_user_data(result)
      count = { "type" => "integer", "minimum" => 0 }
      removed = object({
        "id" => { "type" => "string", "description" => "The removed record, or the record holding the part." },
        "part_ids" => list({ "type" => "string" }, :description => "For a part, its ids from the record down."),
        "user_data_keys" => list({ "type" => "string" },
                                 :description => "The map's first #{Records::Metadata::REPORT_LIMIT} top-level " \
                                                 "keys, sorted, while the report fits its byte limit."),
        "user_data_key_total" => count
      }, :optional => ["part_ids"])
      with(result, "removed_user_data" => list(removed, :description => "Each removed record, then each of its " \
                                                                        "parts, whose user_data was not empty, " \
                                                                        "the first " \
                                                                        "#{Records::Metadata::REPORT_LIMIT} " \
                                                                        "within " \
                                                                        "#{Records::Metadata::REPORT_BYTES} " \
                                                                        "bytes: the map is gone, a survivor " \
                                                                        "keeps its own, and Undo brings it back."),
                   "removed_user_data_total" => count, "removed_user_data_truncated" => DISCARD_TRUNCATED)
    end

    # `schema` with what it means to a caller, for discovery.
    def described(schema, description)
      schema.merge("description" => description)
    end

    # The params of an `update_metadata` action (Records::Metadata): a batch of targets, each with the
    # whole `user_data` map to write, payloads for installed extensions, or both, and the two maps as the
    # caller last read them. `target` names what a reference addresses: an entity owner's occurrence, or a
    # catalog record.
    def metadata_updates(reference, limit, target: "occurrence")
      update = object({
        "reference" => described(reference, "The #{target} to update, as a read returns it."),
        "user_data" => { "type" => "object", "description" => "Replaces the whole user_data map." },
        "extension_payloads" => { "type" => "object", "additionalProperties" => { "type" => "object" },
                                  "description" => "Replaces the payload of each named installed extension." },
        "expected_metadata" => object({ "user_data" => { "type" => "object" },
                                        "extension_data" => { "type" => "object" } },
                                      :description => "The user_data and extension_data last read; a change " \
                                                      "refuses.")
      }, :optional => %w[user_data extension_payloads])
      object({ "updates" => { "type" => "array", "items" => update, "minItems" => 1, "maxItems" => limit,
                              "description" => "The #{target}s to update, written in one step and one Undo." } })
    end

    def metadata_result(reference, target: "occurrence")
      row = object({ "reference" => reference,
                     "extension_status" => { "type" => "object",
                                             "description" => "Each envelope's status after the update." } })
      object({ "updates" => list(row, :description => "Each #{target} the batch names, in order.") })
    end

    # A param naming one record or part by its id, such as `asm_Ab12Cd34Ef56` for prefix "asm".
    def id(prefix, description, nullable: false)
      { "type" => nullable ? %w[string null] : "string", "pattern" => "^#{prefix}_[A-Za-z0-9]{12}$",
        "description" => description }
    end
  end
end
