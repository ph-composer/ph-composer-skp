# frozen_string_literal: true

module PhComposer
  module Mechanical
    # What serves a Zone: a structured extension on the Zone record with one slot per equipment family, as Programs
    # keeps a Zone's assignment (context/CONTRACTS.md, "Mechanical equipment"). It is no record of its own: it has
    # no id, it travels with a copied Zone because it is part of the Zone record, and Zones stages every write of
    # it, so nothing here writes a Zone.
    #
    # A slot holds one item id or null (`one`), or a list of ids held once each (`many`). Each declares its
    # reference, so the engine refuses a plain delete of an item a Zone names as reference.in_use. A later family
    # adds its slot as one line below and moves the schema version.
    #
    # Served by nothing has two stored forms, no payload and a payload whose every slot is empty; the reads answer
    # both alike.
    module Serves
      NAMESPACE = "#{FEATURE_ID}.zone_serves"
      Slot = Struct.new(:key, :kind, :label, :prefix, :cardinality, keyword_init: true) do
        def many?
          cardinality == "many"
        end

        def empty
          many? ? [] : nil
        end

        def id?(value)
          /\A#{prefix}_[A-Za-z0-9]{12}\z/.match?(value.to_s)
        end

        # The slot's value with `from` named `to` instead, or emptied of `from` when `to` is nil.
        def renamed(value, from, to)
          return (value == from ? to : value) unless many?

          value.map { |id| id == from ? to : id }.compact.uniq
        end

        def names?(value, id)
          many? ? value.include?(id) : value == id
        end

        def ids(value)
          many? ? value : [value].compact
        end
      end

      SLOTS = [
        Slot.new(:key => "ventilator_id", :kind => VENTILATOR_KIND, :label => "Ventilator", :prefix => "vnt",
                 :cardinality => "one"),
        Slot.new(:key => "hot_water_system_id", :kind => HOT_WATER_SYSTEM_KIND, :label => "Hot Water System",
                 :prefix => "hws", :cardinality => "one"),
        Slot.new(:key => "hp_indoor_unit_ids", :kind => HP_INDOOR_UNIT_KIND, :label => "Heat Pump Indoor Unit",
                 :prefix => "hiu", :cardinality => "many"),
        Slot.new(:key => "heater_ids", :kind => ELECTRIC_HEATER_KIND, :label => "Electric Heater", :prefix => "ehr",
                 :cardinality => "many"),
        Slot.new(:key => "pump_ids", :kind => PUMP_KIND, :label => "Pump", :prefix => "pmp", :cardinality => "many"),
        Slot.new(:key => "fan_ids", :kind => FAN_KIND, :label => "Fan", :prefix => "fan", :cardinality => "many")
      ].freeze
      KEYS = SLOTS.map(&:key).freeze
      EMPTY = SLOTS.to_h { |slot| [slot.key, slot.empty] }.freeze

      module Payload
        # The Ventilator export claims the namespace on the Zone record (VentilationExport), so a payload this
        # version does not understand blocks the export rather than being left out.
        EXPORT_RELEVANCE = "required"

        module_function

        def slot(key)
          SLOTS.find { |slot| slot.key == key }
        end

        # Every reason `payload` is not a whole payload: each slot present, each id of its slot's kind or null, a
        # list holding no id twice, and no other key.
        def problems(payload)
          extra = payload.keys - KEYS
          missing = KEYS - payload.keys
          found = extra.empty? ? [] : ["unknown fields #{extra.sort.join(', ')}"]
          found << "missing fields #{missing.join(', ')}" unless missing.empty?
          SLOTS.each do |slot|
            next unless payload.key?(slot.key)

            found.concat(slot_problems(slot, payload[slot.key]))
          end
          found
        end

        def slot_problems(slot, value)
          if slot.many?
            ids = value.is_a?(Array) && value.all? { |id| slot.id?(id) }
            return ["#{slot.key} must be a list of #{slot.label} ids"] unless ids

            value.uniq.length == value.length ? [] : ["#{slot.key} holds an id twice"]
          else
            value.nil? || slot.id?(value) ? [] : ["#{slot.key} must be a #{slot.label} id or null"]
          end
        end

        def references
          SLOTS.map do |slot|
            { "path" => "$.#{slot.key}", "target_kind" => slot.kind, "cardinality" => slot.cardinality }
          end
        end

        EXTENSION = Records::Extension.new(:namespace => NAMESPACE, :schema_version => 6,
                                           :references => references, :export_relevance => EXPORT_RELEVANCE,
                                           :validate => ->(payload) { problems(payload) })

        # A Zone's slots from its `extension_data`, and the stored payload's status: nil for none. A payload this
        # version does not understand reads as served by nothing; its status says why. `installed` is the
        # extension the catalog holds for the namespace.
        def read(extension_data, installed)
          envelope = extension_data.fetch(NAMESPACE, nil)
          return [EMPTY.dup, nil] unless envelope

          status = Records::Extension.status(envelope, installed)
          values = status == "understood" ? DeepCopy.call(envelope.fetch("payload")) : EMPTY.dup
          [values, status]
        end

        def served?(values)
          SLOTS.any? { |slot| !slot.ids(values.fetch(slot.key)).empty? }
        end
      end
    end
  end
end
