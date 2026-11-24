# frozen_string_literal: true

module PhComposer
  module Mechanical
    # This feature's Colour-by modes: each Zone in the colour of the item a single Serves slot names, `By
    # ventilator` and `By hot water system`, a later family's single slot the same way. The values are open, so
    # they take the shared categorical ramp, spread so each item differs (Palette.spread_entries).
    #
    # A mode paints Zones' entities, so it gives one entry per row of Zones' occurrence read, one per occurrence,
    # and resolves each row's occurrence path with the core OccurrencePath (context/EXTENSIBILITY.md, "Colour-by
    # modes"). That read leaves every Face out, so an unreadable Face record elsewhere in the Model does not turn a
    # mode off. A Zone its slot leaves empty has no entry and stays uncoloured; a nil value would draw it as
    # unclassified. An item the slot names that is not in the Model is incomplete, under its id.
    module ColourModes
      BY_VENTILATOR = "#{FEATURE_ID}.by_ventilator"
      BY_HOT_WATER_SYSTEM = "#{FEATURE_ID}.by_hot_water_system"
      # Each mode, its label and the single Serves slot whose item colours a Zone.
      MODES = { BY_VENTILATOR => ["Ventilator", "ventilator_id"],
                BY_HOT_WATER_SYSTEM => ["Hot Water System", "hot_water_system_id"] }.freeze
      ZONES = "ph_composer.zones.occurrences"

      module_function

      def install(feature)
        MODES.each do |name, (label, slot)|
          feature.colour_mode(name, :label => label, :entity_kind => "zone",
                                    :colours => ColourBy::Palette.ramp) do |read|
            ColourBy::Palette.spread_entries(entries(read, Serves::Payload.slot(slot)))
          end
        end
      end

      # One entry per Zone occurrence whose `slot` names an item: the item's id as the value and its name as the
      # label.
      def entries(read, slot)
        installed = read.registry.catalog.extension(Serves::NAMESPACE)
        names = item_names(read.engine, slot.kind)
        read.query(ZONES).fetch("zones").filter_map do |row|
          values, _status = Serves::Payload.read(row.fetch("extension_data", {}), installed)
          id = values.fetch(slot.key)
          next unless id

          path = row.dig("reference", "zone_path")
          resolved = resolve(read.model, path)
          next unless resolved

          ColourBy::Entry.new(:entity => resolved.instances.last, :transform => resolved.transform, :path => path,
                              :value => id, :label => names.fetch(id, id),
                              :state => names.key?(id) ? nil : :incomplete)
        end
      end

      # A row's occurrence, or nil when its path no longer resolves to one Group (a path the read answered moments
      # ago): that Zone is left uncoloured rather than turning the whole mode off.
      def resolve(model, path)
        OccurrencePath.resolve(model, path)
      rescue CodedError
        nil
      end

      # The stored items of `kind` by id, their names; an unreadable item reads under its id.
      def item_names(engine, kind)
        records, unreadable = DefinitionLists.read(engine, kind, engine.ids(kind))
        records.to_h { |record| [record.fetch("id"), record.fetch("name")] }
               .merge(unreadable.to_h { |row| [row.fetch("id"), row.fetch("id")] })
      end
    end
  end
end
