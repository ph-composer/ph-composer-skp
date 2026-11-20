# frozen_string_literal: true

require_relative "../../core/model_settings"

module PhComposer
  module Programs
    # The Model's default Program and default Equipment Set: the Program unassigned Zones and Single dwelling use,
    # and the Set a Dwelling with none of its own uses (context/CONTRACTS.md, "Programs, Schedules and Equipment
    # Sets"). One dictionary holds both. A field stored as null, or absent, means PH-Composer's own default under its
    # reserved id, so a fresh Model stores nothing; the reserved id is never stored. A settings proposal guards its
    # whole dictionary, so each update guards only the fields it names and takes the other as it reads now: an
    # update of one default never stales a pending update of the other (Climate split its dictionaries for the
    # same reason, context/CONTRACTS.md, "Model settings").
    module Settings
      DICTIONARY = "#{FEATURE_ID}.settings"
      KIND = "#{FEATURE_ID}.settings_record"
      SLOT_ID = "pst_ModelDefaults"
      FIELDS = { "default_program_id" => [PROGRAM_KIND, DefaultProgram::PROGRAM_ID],
                 "default_equipment_set_id" => [EQUIPMENT_SET_KIND, DefaultEquipmentSet::SET_ID] }.freeze
      DEFAULTS = FIELDS.keys.to_h { |key| [key, nil] }.freeze
      STORED = SchemaShapes.object(FIELDS.keys.to_h { |key| [key, { "type" => %w[string null] }] }).freeze
      SERVICE = ModelSettings.new(:dictionary => DICTIONARY, :defaults => DEFAULTS, :schema => STORED,
                                  :label => "Programs", :step_name => "update_programs_settings",
                                  :affected => [{ "kind" => "programs_settings", "id" => FEATURE_ID,
                                                  "change" => "updated" }])

      module_function

      # The stored defaults, null for PH-Composer's own.
      def stored(model)
        SERVICE.read(model)
      end

      # The effective defaults, each a record id: the stored one or the reserved id.
      def read(model)
        stored(model).to_h { |key, value| [key, value || FIELDS.fetch(key).last] }
      end

      def kind_field(kind)
        FIELDS.find { |_key, (field_kind, _reserved)| field_kind == kind }.first
      end

      # The effective default of `kind`.
      def default_id(model, kind)
        read(model).fetch(kind_field(kind))
      end

      # Stages `values` (effective ids by field) over the stored defaults; each reserved id stores as null.
      def propose(request, proposal, values)
        before = stored(request.model)
        after = before.merge(values.to_h { |key, id| [key, id == FIELDS.fetch(key).last ? nil : id] })
        SERVICE.propose(request.model, proposal, :values => after, :expected_values => before)
      end

      def entry(values)
        Records::ReferenceEntry.new(:kind => KIND, :key => DICTIONARY, :record => values.merge("id" => SLOT_ID))
      end

      # The stored defaults as a reference source, so a stored default refuses its record's plain delete
      # (reference.in_use) and a delete with a replacement moves it (`retarget`).
      TARGET = Records::ReferenceTarget.new(
        :id => KIND, :label => "Programs defaults", :schema_version => 1, :values => STORED,
        :records => ->(model) { [entry(stored(model))] },
        :validate => lambda { |record|
          (record["id"] == SLOT_ID ? [] : ["The Model settings identity is invalid."]) +
            JsonSchema.validate(record.reject { |key, _| key == "id" }, STORED)
        },
        :references => FIELDS.map do |key, (kind, _reserved)|
          Records::Reference.new(:key => key, :target_kind => kind, :cardinality => "one")
        end
      )

      # Moves the default from `from` to `to`, inside a delete that names a replacement. The default compared is the
      # effective one, so deleting the stored residential default while the field is null moves it too.
      def retarget(request, proposal, kind, from:, to:)
        key = kind_field(kind)
        before = stored(request.model)
        return Records::ReferencePlan.new(:entries => []) unless read(request.model)[key] == from

        propose(request, proposal, key => to)
        Records::ReferencePlan.new(:entries => [entry(stored_after(before, key, to))])
      end

      def stored_after(before, key, id)
        before.merge(key => id == FIELDS.fetch(key).last ? nil : id)
      end

      def install(feature)
        feature.reference_target(TARGET)
        FIELDS.each do |key, (kind, _reserved)|
          feature.reference_retargeter("#{FEATURE_ID}.settings.retarget_#{key.delete_suffix('_id')}",
                                       :target_kind => kind) do |request, proposal, from:, to:|
            retarget(request, proposal, kind, :from => from, :to => to)
          end
        end
      end
    end
  end
end
