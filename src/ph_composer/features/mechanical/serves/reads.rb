# frozen_string_literal: true

module PhComposer
  module Mechanical
    module Serves
      # The Serves reads. `serves.all` answers every Zone occurrence with its slots, the items they name and the
      # Zone's findings; `serves.list` pages the same rows. Each family's item reads gain the Zones each item
      # serves and its own findings from `usage`. Every row comes from one `ph_composer.zones.all` read per call,
      # with no walk of the Model here.
      #
      # Findings report what the generic metadata routes can store but the feature's own actions refuse, and what
      # the export will do (context/CONTRACTS.md, "Mechanical equipment"). Only a missing item blocks the export.
      module Reads
        LIST = "#{FEATURE_ID}.serves.list"
        SPACES = "ph_composer.spaces.all"
        PROGRAMS = "ph_composer.programs.zones"

        module_function

        def all(request)
          { "zones" => rows(request) }
        end

        def list(request)
          rows = rows(request)
          page, next_cursor = Pages.bounded(request, LIST, rows, :key => ->(row) { key(row) })
          { "zones" => page, "next_cursor" => next_cursor, "total" => rows.length }
        end

        # A row per Zone occurrence, in Zone id then occurrence path order.
        def rows(request)
          zones = State.zones(request)
          names = item_names(request)
          zones.map { |zone| zone_row(zone, names) }.sort_by { |row| key(row) }
        end

        def key(row)
          [row.fetch("zone_id"), row.dig("reference", "zone_path")]
        end

        def zone_row(zone, names)
          items = SLOTS.flat_map do |slot|
            slot.ids(zone.values.fetch(slot.key)).map do |id|
              { "slot" => slot.key, "id" => id, "name" => names.fetch(slot.kind).fetch(id, nil),
                "missing" => !names.fetch(slot.kind).key?(id) }
            end
          end
          { "zone_id" => zone.id, "reference" => zone.reference, "name" => zone.name,
            "building_segment_id" => zone.segment_id, "building_segment" => zone.segment, "slots" => zone.values,
            "payload_status" => zone.status,
            "items" => items.map { |item| item.reject { |key, _value| key == "missing" } },
            "findings" => zone_findings(zone, items) }
        end

        def zone_findings(zone, items)
          found = items.select { |item| item.fetch("missing") }.map do |item|
            finding(Codes::ITEM_MISSING, "error", "#{item.fetch('slot')} on Zone #{label(zone)} names " \
                                                  "#{item.fetch('id')}, which is not in the Model.")
          end
          if zone.left_out
            unless items.empty?
              found << finding(Codes::ZONE_LEFT_OUT, "info", "Zone #{label(zone)} is in no Building Segment, so " \
                                                             "the export leaves its Room out.")
            end
          elsif zone.values.fetch("ventilator_id").nil?
            found << finding(Codes::ZONE_UNVENTILATED, "warning", "Zone #{label(zone)} has no Ventilator.")
          end
          found
        end

        # What an item read adds to each row of `kind`: the Zone occurrences it serves and its findings, from one
        # Zones read, and with `with_balance` its airflow balance over them (`balance`).
        def usage(request, kind, with_balance: false)
          slots = SLOTS.select { |slot| slot.kind == kind }
          zones = State.zones(request)
          balanced = with_balance ? balance(request) : nil
          lambda do |record|
            id = record.fetch("id")
            served = zones.select { |zone| slots.any? { |slot| slot.names?(zone.values.fetch(slot.key), id) } }
            rows = served.map { |zone| { "zone_id" => zone.id, "reference" => zone.reference, "name" => zone.name } }
            extra = { "zones" => rows, "findings" => item_findings(record, served) }
            balanced ? extra.merge("balance" => balanced.call(served)) : extra
          end
        end

        # An item's airflow balance over the Zones it serves (Balance), from one Spaces read and one Programs read
        # that every row shares, each Zone found by its occurrence path. The Zones counted are those the export
        # writes the item to: each Zone once, its first occurrence by path, and none in no Building Segment.
        #
        # A Spaces read that refuses (an unreadable Space anywhere in the Model) leaves every row's balance unknown
        # with its message; a Programs read that refuses leaves unknown only a balance that needs a By Program
        # Zone's flow. Either way the Ventilators still read.
        def balance(request)
          spaces = request.query(SPACES).fetch("zones").to_h { |row| [row.fetch("zone_path"), row] }
          programs, refusal = program_rows(request)
          lambda do |served|
            exported = served.reject(&:left_out).sort_by { |zone| zone.reference.fetch("zone_path") }.uniq(&:id)
            Balance.call(exported.map do |zone|
              path = zone.reference.fetch("zone_path")
              Balance::Zone.new(:name => label(zone), :spaces => spaces[path], :programs => programs[path])
            end, :programs_refusal => refusal)
          end
        rescue CodedError => error
          ->(_served) { Balance.unreadable(error.message) }
        end

        # Programs' Zone rows by occurrence path, and the message of its refusal when it cannot be read.
        def program_rows(request)
          [request.query(PROGRAMS).fetch("zones").to_h { |row| [row.dig("reference", "zone_path"), row] }, nil]
        rescue CodedError => error
          [{}, error.message]
        end

        def item_findings(record, served)
          name = record.fetch("name")
          return [finding(Codes::ITEM_UNSERVED, "warning", "#{name} serves no Zone, so nothing exports it.")] if
            served.empty?

          served.select(&:left_out).map do |zone|
            finding(Codes::ZONE_LEFT_OUT, "info", "#{name} serves Zone #{label(zone)}, which is in no Building " \
                                                  "Segment, so the export leaves that Room out.")
          end
        end

        # Each slot kind's stored items by id, their names; an unreadable item is present with no name.
        def item_names(request)
          SLOTS.map(&:kind).uniq.to_h do |kind|
            records, unreadable = DefinitionLists.read(request.engine, kind, request.engine.ids(kind))
            [kind, records.to_h { |record| [record.fetch("id"), record.fetch("name")] }
                          .merge(unreadable.to_h { |row| [row.fetch("id"), nil] })]
          end
        end

        def finding(code, severity, message)
          { "code" => code, "severity" => severity, "message" => message, "blocks_export" => severity == "error" }
        end

        def label(zone)
          zone.name || zone.id
        end
      end
    end
  end
end
