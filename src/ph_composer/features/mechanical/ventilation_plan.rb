# frozen_string_literal: true

module PhComposer
  module Mechanical
    # The Ventilator export worked out once, in pure Ruby over plain values, so the export contributor and the
    # preflight read the same pairs and the same findings (context/CONTRACTS.md, "Mechanical equipment"). The
    # Python section builds honeybee-ph objects from the pairs and computes nothing.
    #
    # One pair per (Ventilator, exported Zone) the Ventilator serves. Every pair of one Ventilator carries the same
    # values and the identifiers derived from its id, so honeybee-ph reloads one system for them all and PHX keys one
    # device. A Ventilator that serves no Zone, and a Zone in no Building Segment, give no pair; each has its finding.
    module VentilationPlan
      # The unit's values each pair carries, as the Ventilator stores them; the two optional ones null when absent.
      UNIT_FIELDS = %w[quantity sensible_heat_recovery latent_heat_recovery electric_efficiency_wh_m3
                       frost_protection_reqd temperature_below_defrost_used_c in_conditioned_space
                       subsoil_heat_exchange_efficiency preheated_intake_temperature_c].freeze
      UNIT_SUFFIX = "_unit"

      # One Zone, once per Zone id: `segment` names its Building Segment (nil when it is in none), `exported`
      # says whether the export writes its Room, and `values` are its Serves slots.
      Zone = Struct.new(:id, :name, :segment, :exported, :values, keyword_init: true) do
        def label
          name || id
        end

        def ventilator_id
          values.fetch("ventilator_id")
        end
      end
      # `record_id` is the row's object: a Zone for a Zone's finding, a Ventilator for an item's.
      Finding = Struct.new(:code, :record_id, :message, :blocks, keyword_init: true)
      Plan = Struct.new(:pairs, :findings, keyword_init: true)

      module_function

      # `zones` are Zone values, one per Zone id; `ventilators` maps each stored Ventilator's id to its values,
      # with its `name` and, where the caller passes it through, its `user_data`. `unreadable` are the ids of stored
      # Ventilators that cannot be read, which the caller reports itself: a Zone naming one is not missing one.
      def call(zones:, ventilators:, unreadable: [])
        exported, left_out = zones.sort_by(&:id).partition(&:exported)
        Plan.new(:pairs => pairs(exported, ventilators),
                 :findings => zone_findings(exported, ventilators, unreadable) +
                              item_findings(exported, left_out, ventilators))
      end

      def pairs(zones, ventilators)
        zones.filter_map do |zone|
          item = ventilators[zone.ventilator_id]
          item && pair(zone.ventilator_id, item, zone)
        end.sort_by { |row| row.fetch("id") }
      end

      def pair(item_id, item, zone)
        row = { "id" => "#{item_id}_#{zone.id}", "item_id" => item_id, "zone_id" => zone.id,
                "system_identifier" => item_id, "unit_identifier" => "#{item_id}#{UNIT_SUFFIX}",
                "display_name" => item.fetch("name") }
        UNIT_FIELDS.each { |key| row[key] = item.fetch(key, nil) }
        item.key?("user_data") ? row.merge("user_data" => DeepCopy.call(item.fetch("user_data"))) : row
      end

      # An exported Zone with no Ventilator, or one naming a Ventilator that is not stored.
      def zone_findings(zones, ventilators, unreadable)
        zones.filter_map do |zone|
          id = zone.ventilator_id
          if id.nil?
            Finding.new(:code => Codes::ZONE_UNVENTILATED, :record_id => zone.id, :blocks => false,
                        :message => "Zone #{zone.label} has no Ventilator.")
          elsif !ventilators.key?(id) && !unreadable.include?(id)
            Finding.new(:code => Codes::ITEM_MISSING, :record_id => zone.id, :blocks => true,
                        :message => "ventilator_id on Zone #{zone.label} names #{id}, which is not in the Model.")
          end
        end
      end

      # Per Ventilator: serving no Zone, each served Zone the export leaves out, and Zones in more than one
      # Building Segment.
      def item_findings(exported, left_out, ventilators)
        ventilators.keys.sort.flat_map do |id|
          name = ventilators.fetch(id).fetch("name")
          served = exported.select { |zone| zone.ventilator_id == id }
          gone = left_out.select { |zone| zone.ventilator_id == id }
          next [unserved(id, name)] if served.empty? && gone.empty?

          gone.map { |zone| left_out(id, name, zone) } + across_segments(id, name, served)
        end
      end

      def unserved(id, name)
        Finding.new(:code => Codes::ITEM_UNSERVED, :record_id => id, :blocks => false,
                    :message => "#{name} serves no Zone, so nothing exports it.")
      end

      def left_out(id, name, zone)
        Finding.new(:code => Codes::ZONE_LEFT_OUT, :record_id => id, :blocks => false,
                    :message => "#{name} serves Zone #{zone.label}, which is in no Building Segment, so the export " \
                                "leaves that Room out.")
      end

      def across_segments(id, name, served)
        segments = served.map(&:segment).uniq.sort
        return [] if segments.length < 2

        [Finding.new(:code => Codes::ITEM_ACROSS_SEGMENTS, :record_id => id, :blocks => false,
                     :message => "#{name} serves Zones in #{segments.length} Building Segments " \
                                 "(#{segments.join(', ')}); each Segment's model carries the whole Ventilator.")]
      end
    end
  end
end
