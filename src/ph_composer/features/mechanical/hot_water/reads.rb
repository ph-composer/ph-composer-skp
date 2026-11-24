# frozen_string_literal: true

module PhComposer
  module Mechanical
    module HotWater
      # Detached rows for the reads and the panel snapshot: each record as stored, with its metadata, its extension
      # payloads' status and whether it can export. `extra` adds what a caller composes beside a row, built from the
      # record. What a kind adds of its own comes from the hot water records alone: a System its Heater and Tank
      # counts and its recirculation, a Tank the slot it fills.
      module Reads
        LISTS = { Systems::KIND_ID => "#{FEATURE_ID}.hot_water_systems.list",
                  Heaters::KIND_ID => "#{FEATURE_ID}.hot_water_heaters.list",
                  Tanks::KIND_ID => "#{FEATURE_ID}.hot_water_tanks.list" }.freeze

        module_function

        def all(request, kind, extra: nil)
          DefinitionLists.all(request.engine, kind) { |record| row(request.engine, kind, record, extra) }
        end

        def list(request, kind, extra: nil)
          DefinitionLists.list(request, LISTS.fetch(kind), kind) { |record| row(request.engine, kind, record, extra) }
        end

        # Every stored hot water record is complete, so none is kept out of an export by its own values; the row
        # carries the list so every equipment family reads alike.
        def row(engine, kind, record, extra = nil)
          engine.view(kind, record).merge("export_ready" => true, "export_blockers" => [])
                .merge(extra ? extra.call(record) : {})
        end

        # What a System row adds of the hot water records: how many readable Heaters and Tanks name it, and its
        # recirculation temperature and hours, read-only. They come from recirculation piping, and until a System
        # has any they are honeybee-ph's defaults, which is what the export carries.
        def system_extra(request)
          counts = MEMBER_KINDS.to_h do |kind|
            [kind, members(request.engine, kind).map { |record| record.fetch("hot_water_system_id") }.tally]
          end
          lambda do |record|
            id = record.fetch("id")
            { "heater_count" => counts.fetch(Heaters::KIND_ID).fetch(id, 0),
              "tank_count" => counts.fetch(Tanks::KIND_ID).fetch(id, 0),
              "recirculation" => Systems::RECIRCULATION_DEFAULTS.merge("from_piping" => false) }
          end
        end

        # What a Tank row adds: the slot it fills among its System's Tanks (Slotting), or null with a
        # mechanical.tank_unslotted finding.
        def tank_extra(request)
          tanks = members(request.engine, Tanks::KIND_ID).group_by { |record| record.fetch("hot_water_system_id") }
          slotted = tanks.transform_values { |group| Slotting.call(group) }
          lambda do |record|
            slot = slotted.fetch(record.fetch("hot_water_system_id")).slot_of(record.fetch("id"))
            findings = slot ? [] : [Codes.finding(Codes::TANK_UNSLOTTED, "warning", unslotted_message(record))]
            { "slot" => slot, "findings" => findings }
          end
        end

        def unslotted_message(tank)
          "#{tank.fetch('name')} is a #{tank.fetch('role')} tank with no free #{tank.fetch('role')} slot on its " \
            "System, so the export leaves it out."
        end

        # The readable records of `kind`; an unreadable one is reported by its own read.
        def members(engine, kind)
          DefinitionLists.read(engine, kind, engine.ids(kind).sort).first
        end
      end
    end
  end
end
