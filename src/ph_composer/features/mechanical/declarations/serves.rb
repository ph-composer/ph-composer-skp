# frozen_string_literal: true

module PhComposer
  module Mechanical
    # What Serves registers: the extension on the Zone record, the `mechanical` codes, Assign and Clear, and the
    # reads with their snapshot section. Both actions stage through Zones' participant, one Undo step each.
    module ServesRegistration
      PREFIX = "#{FEATURE_ID}.serves".freeze
      STAGE = Serves::State::STAGE
      READ = Serves::State::REFUSES
      PAGE = %w[query.cursor_expired query.limit_invalid].freeze
      # Its own refusals; the dispatcher adds the participant's (Zones' target.* and extension.* codes).
      WRITE = (READ + %w[record.unreadable reference.invalid target.ambiguous target.changed target.not_found
                         validation.failed]).uniq.sort.freeze
      ASSIGN = (WRITE + [Codes::SLOT_FILLED]).sort.freeze
      # Each slot's value: one id or null, or a list of ids.
      SLOT_IDS = Serves::SLOTS.to_h do |slot|
        id = Shapes.id(slot.prefix, "A #{slot.label}.", :nullable => !slot.many?)
        schema = slot.many? ? Shapes.list(id, :description => "Its #{slot.label}s, empty for none.") :
                              Shapes.described(id, "Its #{slot.label}, null for none.")
        [slot.key, schema]
      end.freeze
      SLOTS = Shapes.object(SLOT_IDS).freeze
      SLOT = { "type" => "string", "enum" => Serves::KEYS,
               "description" => "The family slot: #{Serves::KEYS.join(', ')}." }.freeze
      TARGET = Shapes.object({
        "reference" => Zones::ZONE_REFERENCE,
        "expected_values" => Shapes.described(Shapes.object(SLOT_IDS, :optional => Serves::KEYS),
                                              "Any of the Zone's slots as serves.all last read them; if one " \
                                              "changed since, the command is refused as target.changed. {} skips " \
                                              "the check.")
      }, :optional => ["expected_values"]).freeze
      TARGETS = Shapes.list(TARGET, :description => "Each Zone occurrence, as serves.all or zones.all returns its " \
                                                    "reference.").merge("minItems" => 1).freeze
      ITEM_ID = { "type" => "string", "pattern" => "^[a-z]{3}_[A-Za-z0-9]{12}$",
                  "description" => "The item the slot names; its id is of the slot's kind." }.freeze
      ZONE_EXAMPLE = { "reference" => { "zone_id" => "zon_Ab12Cd34Ef56", "zone_path" => [101] },
                       "expected_values" => { "ventilator_id" => nil } }.freeze
      FINDING = Shapes.object({ "code" => Shapes::TEXT, "severity" => { "type" => "string",
                                                                        "enum" => %w[error warning info] },
                                "message" => Shapes::TEXT,
                                "blocks_export" => { "type" => "boolean" } }).freeze
      FINDINGS = Shapes.list(FINDING).freeze
      ITEM = Shapes.object({ "slot" => SLOT, "id" => Shapes::TEXT,
                             "name" => Shapes.described({ "type" => %w[string null] },
                                                        "Null for an item that is not in the Model or cannot be " \
                                                        "read.") }).freeze
      ROW = Shapes.object({
        "zone_id" => Shapes::TEXT, "reference" => Zones::ZONE_REFERENCE, "name" => { "type" => %w[string null] },
        "building_segment_id" => Shapes.described({ "type" => %w[string null] },
                                                  "Null in No Building Segment, and for a Zone not yet adopted, " \
                                                  "which names its Segment by text."),
        "building_segment" => Shapes.described({ "type" => %w[string null] },
                                               "Its Building Segment's name, or the name a Zone not yet adopted " \
                                               "carries; null in none."),
        "slots" => Shapes.described(SLOTS, "What serves it, every slot empty when it stores none."),
        "payload_status" => Shapes.described({ "type" => %w[string null] },
                                             "The stored payload's status, null for none; any but understood reads " \
                                             "as served by nothing."),
        "items" => Shapes.list(ITEM, :description => "The items its slots name, with their names."),
        "findings" => FINDINGS
      }).freeze
      LIST_PARAMS = Shapes.object({ "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR },
                                  :optional => Pages::PAGE_KEYS).freeze
      # What an item read's rows gain: the Zones each item serves and its findings.
      SERVED = { "zones" => Shapes.list(Shapes.object({ "zone_id" => Shapes::TEXT,
                                                        "reference" => Zones::ZONE_REFERENCE,
                                                        "name" => { "type" => %w[string null] } }),
                                        :description => "Each Zone occurrence it serves."),
                 "findings" => FINDINGS }.freeze

      module_function

      def install(feature)
        feature.extension(Serves::Payload::EXTENSION)
        Codes.install(feature)
        install_reads(feature)
        install_assign(feature)
        install_clear(feature)
      end

      def install_reads(feature)
        feature.query(Serves::Reads::LIST, :description => "One bounded page of Zone occurrences with what serves " \
                                                           "each, in Zone id order, and their findings.",
                                           :refuses => READ + PAGE, :params => LIST_PARAMS,
                                           :result => Shapes.object({ "zones" => Shapes.list(ROW),
                                                                      "next_cursor" => Pages::NEXT_CURSOR,
                                                                      "total" => Pages::TOTAL }),
                                           :examples => [{}, { "limit" => 20 }]) do |request|
          Serves::Reads.list(request)
        end
        feature.query("#{PREFIX}.all", :description => "Every Zone occurrence with what serves each, the items' " \
                                                       "names and the findings, for the panel snapshot.",
                                       :response => { "bounded" => false, "prefer" => Serves::Reads::LIST },
                                       :refuses => READ, :params => Shapes::NONE,
                                       :result => Shapes.object({ "zones" => Shapes.list(ROW) }),
                                       :examples => [{}]) { |request| Serves::Reads.all(request) }
        feature.snapshot_section(PREFIX, :query => "#{PREFIX}.all")
      end

      def install_assign(feature)
        params = Shapes.object({ "zones" => TARGETS, "slot" => SLOT, "item_id" => ITEM_ID,
                                 "replace" => { "type" => "boolean",
                                                "description" => "Replace an item already in a single slot; " \
                                                                 "without it that Zone refuses " \
                                                                 "#{Codes::SLOT_FILLED}, naming the item." } },
                               :optional => ["replace"])
        result = Shapes.object({ "zone_ids" => Shapes.list(Shapes::TEXT, :description => "The Zones named."),
                                 "slot" => SLOT, "item_id" => Shapes::TEXT })
        feature.action("#{PREFIX}.assign",
                       :description => "Name an item in one slot of Zones. A single slot holds one item (a " \
                                       "Ventilator serves a Zone alone); a list slot, hp_indoor_unit_ids, adds it " \
                                       "beside the items it holds.",
                       :refuses => ASSIGN, :params => params, :result => result, :participants => [STAGE],
                       :undo_name => "Assign Equipment",
                       :preconditions => ["The item exists.", "Each Zone is writable: no locked Group, shared " \
                                                              "definition or containing Zone."],
                       :side_effects => "Writes each Zone's Serves payload; Programs' assignment is untouched.",
                       :examples => [{ "zones" => [ZONE_EXAMPLE], "slot" => "ventilator_id",
                                       "item_id" => "vnt_Ab12Cd34Ef56" }]) do |request, proposal|
          params = request.params
          Serves::Operations.assign(request, proposal, :targets => params.fetch("zones"),
                                                       :slot => params.fetch("slot"),
                                                       :item_id => params.fetch("item_id"),
                                                       :replace => params.fetch("replace", false))
        end
      end

      def install_clear(feature)
        params = Shapes.object({ "zones" => TARGETS,
                                 "slot" => SLOT.merge("description" => "The slot to empty; every slot when absent."),
                                 "item_id" => ITEM_ID.merge("description" => "Take only this item out of the slot, " \
                                                                             "which a list slot needs; the slot " \
                                                                             "must be given.") },
                               :optional => %w[slot item_id])
        result = Shapes.object({ "zone_ids" => Shapes.list(Shapes::TEXT, :description => "The Zones named, written " \
                                                                                         "or already empty."),
                                 "slot" => { "type" => %w[string null] } })
        feature.action("#{PREFIX}.clear",
                       :description => "Empty one slot of Zones, or every slot, so they read as served by nothing; " \
                                       "with item_id, take only that item out of the slot.",
                       :refuses => WRITE, :params => params, :result => result, :participants => [STAGE],
                       :undo_name => "Clear Equipment",
                       :preconditions => ["Each Zone is writable: no locked Group, shared definition or containing " \
                                          "Zone."],
                       :side_effects => "Writes each Zone's Serves payload; a Zone that stores none is left as it " \
                                        "is.",
                       :examples => [{ "zones" => [ZONE_EXAMPLE] }]) do |request, proposal|
          Serves::Operations.clear(request, proposal, :targets => request.params.fetch("zones"),
                                                      :slot => request.params["slot"],
                                                      :item_id => request.params["item_id"])
        end
      end
    end
  end
end
