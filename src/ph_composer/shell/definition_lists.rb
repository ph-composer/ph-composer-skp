# frozen_string_literal: true

require "json"

module PhComposer
  # The list and all reads of a Model-owned definition kind: Materials, Assemblies, the Window
  # products and Types, Thermal Bridge Types. The owning feature gives the kind and how to build one
  # row from a stored record. This module reads the records and reports an unreadable one beside the
  # rows, never repaired or dropped. For the list, it also filters by `ids`, projects each row to
  # `fields` and cuts a page by size (shell/pages.rb), so one oversized row can be read past by asking
  # for fewer fields.
  module DefinitionLists
    # What a row carries whatever `fields` asks.
    IDENTITY = %w[kind id schema_version].freeze
    UNREADABLE = SchemaShapes.list(
      SchemaShapes.object(%w[id code message].to_h { |key| [key, { "type" => "string" }] })
    ).freeze

    module_function

    # Every record of `kind_id` in id order, each as `row` builds it, for a panel snapshot.
    def all(engine, kind_id, &row)
      records, unreadable = read(engine, kind_id, engine.ids(kind_id).sort)
      { "records" => records.map(&row), "unreadable" => unreadable }
    end

    # One page in id order. A row is built only when the page reaches its id, and only once.
    def list(request, query, kind_id, &row)
      engine = request.engine
      ids = engine.ids(kind_id).sort
      ids &= request.params["ids"] if request.params.key?("ids")
      fields = request.params["fields"]
      entries = Hash.new { |built, id| built[id] = entry(engine, kind_id, id, fields, row) }
      size = ->(id) { JSON.generate(entries[id].last).bytesize + 1 }
      page, next_cursor = Pages.bounded(request, query, ids, :key => ->(id) { id }, :size => size)
      rows, unreadable = page.map { |id| entries[id] }.partition(&:first)
      { "records" => rows.map(&:last), "unreadable" => unreadable.map(&:last), "next_cursor" => next_cursor,
        "total" => ids.length }
    end

    # [records, unreadable] for `ids`: each stored record, or why the engine cannot use it.
    def read(engine, kind_id, ids)
      entries = ids.map { |id| entry(engine, kind_id, id, nil, ->(record) { record }) }
      readable, unreadable = entries.partition(&:first)
      [readable.map(&:last), unreadable.map(&:last)]
    end

    # [readable, row]: the record as `row` builds it and projected to `fields`, or why the engine
    # cannot read it. Only the read is rescued; a refusal raised while building a row is the builder's
    # and propagates.
    def entry(engine, kind_id, id, fields, row)
      record = engine.find(kind_id, id)
    rescue CodedError => error
      raise unless error.code == "record.unreadable"

      [false, { "id" => id, "code" => error.code, "message" => error.message }]
    else
      whole = row.call(record)
      [true, fields ? whole.slice(*(IDENTITY + fields)) : whole]
    end

    # A list's params. `fields` names any of `row`'s properties beside its identity.
    def params(row)
      fields = row.fetch("properties").keys - IDENTITY
      SchemaShapes.object({
        "ids" => SchemaShapes.list({ "type" => "string" }).merge("maxItems" => Pages::MAXIMUM_LIMIT,
                                                                 "description" => "Only these record ids; every " \
                                                                                  "record when absent."),
        "fields" => SchemaShapes.list({ "type" => "string", "enum" => fields },
                                      :description => "What each row carries beside kind, id and schema_version; " \
                                                      "the whole row when absent. Ask for fewer when a row is " \
                                                      "larger than your reply."),
        "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR
      }, :optional => %w[ids fields limit cursor])
    end

    # A list's result (`paged`) or the all read's. A list row requires only its identity, since `fields`
    # can leave the rest out. `extra` names more properties the result carries.
    def result(row, paged:, extra: {})
      row = row.merge("required" => IDENTITY & row.fetch("required")) if paged
      properties = { "records" => SchemaShapes.list(row), "unreadable" => UNREADABLE }.merge(extra)
      properties.merge!("next_cursor" => Pages::NEXT_CURSOR, "total" => Pages::TOTAL) if paged
      SchemaShapes.object(properties)
    end
  end
end
