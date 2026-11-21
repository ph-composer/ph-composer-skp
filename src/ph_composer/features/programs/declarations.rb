# frozen_string_literal: true

module PhComposer
  module Programs
    module Shapes
      extend SchemaShapes

      TEXT = { "type" => "string" }.freeze
      OBJECT = { "type" => "object" }.freeze
      NONE = object({}).freeze
      RESULT = object({ "id" => TEXT }).freeze
      DEVICE_RESULT = object({ "id" => TEXT, "device_id" => TEXT }).freeze
      COUNT = { "type" => "integer", "minimum" => 0 }.freeze
      EXPECTED = "Any of the values as last read; if one changed since, the edit is refused as target.changed. {} " \
                 "skips the check."
      # Open, so one describe of a Program's edit fits a reply: the values schema is the record's own.
      EXPECTED_VALUES = { "type" => "object", "description" => EXPECTED }.freeze
      USER_DATA = { "type" => "object",
                    "description" => "Local JSON metadata kept with the record in the Model." }.freeze
      STORED = described({ "type" => "boolean" }, "False for PH-Composer's default while the Model holds none of " \
                                                  "it: reads answer its definition until a write stores it.")

      module_function

      def view(kind)
        with(kind.descriptor.view_schema, "kind" => TEXT, "extension_status" => OBJECT, "stored" => STORED)
      end

      def create(kind)
        values = DeepCopy.call(kind.values_schema).merge("required" => [])
        object({ "values" => described(values, "The new #{kind.label}'s values; any not given take their " \
                                               "defaults, and a missing name the first free \"#{kind.label} N\"."),
                 "user_data" => USER_DATA }, :optional => %w[values user_data])
      end

      # An Equipment Set's devices are left out: the device actions change them.
      def update(kind)
        patch = kind.descriptor.patch_schema
        patch["properties"].delete("devices")
        object({ "id" => id(kind.id_prefix, "The #{kind.label} to edit."),
                 "values" => described(patch, "The values to change; any not given stay."),
                 "expected_values" => EXPECTED_VALUES })
      end

      # A device's own values, every one optional; `nullable` for an edit, where null removes one.
      def device_values(nullable:)
        properties = EquipmentTypes::DEVICE.fetch("properties").reject { |key, _| %w[id type user_data].include?(key) }
        properties = properties.transform_values { |schema| DeepCopy.call(schema) }
        if nullable
          properties.each_value do |schema|
            schema["type"] = (Array(schema["type"]) + ["null"]).uniq
            schema["enum"] += [nil] if schema["enum"]
          end
        end
        object(properties, :optional => properties.keys)
      end
    end

    # The codes Programs operations refuse with beyond the common sets (context/CONTRACTS.md, "Outcomes and
    # codes"). Every write goes through the record engine or Store.
    module Refuses
      PAGE = %w[query.cursor_expired query.limit_invalid].freeze
      # The collections' reads count occupancy uses, which reads the Zones (OccupancyState).
      USES = %w[geometry.invalid record.unreadable target.wrong_kind validation.failed].freeze
      READ = %w[record.unreadable].freeze
      CREATE = %w[record.unreadable reference.invalid target.ambiguous target.not_found validation.failed].freeze
      EDIT = %w[record.unreadable reference.invalid target.ambiguous target.changed target.not_found
                validation.failed].freeze
      DUPLICATE = %w[copy.rule_missing extension.invalid record.unreadable reference.invalid target.ambiguous
                     target.not_found validation.failed].freeze
      DELETE = %w[copy.rule_missing programs.default_in_use record.unreadable reference.in_use reference.invalid
                  target.ambiguous target.changed target.not_found target.wrong_kind validation.failed].freeze
      # A Program's or Equipment Set's delete with a replacement stages the Zones and Segments naming it through
      # Zones, which refuses as any Zone write does.
      DELETE_STAGED = (DELETE + USES +
                       %w[extension.invalid extension.migration_required extension.schema_unsupported
                          extension.unavailable target.locked target.shared_definition target.wrong_hierarchy])
                      .uniq.sort.freeze
    end

    # The Programs, Schedules and Equipment Sets operations and reads (context/CONTRACTS.md, "Programs, Schedules
    # and Equipment Sets").
    module Declarations
      COLLECTIONS = { "programs" => Program::KIND, "schedules" => Schedule::KIND,
                      "equipment_sets" => EquipmentSet::KIND, "dwellings" => Dwelling::KIND }.freeze
      EXAMPLES = { "programs" => "pgm_Ab12Cd34Ef56", "schedules" => "sch_Ab12Cd34Ef56",
                   "equipment_sets" => "eqs_Ab12Cd34Ef56", "dwellings" => "dwl_Ab12Cd34Ef56" }.freeze
      DEVICES = "#{FEATURE_ID}.equipment_sets".freeze
      SET_ID = SchemaShapes.id("eqs", "The Equipment Set.").freeze
      DEVICE_ID = SchemaShapes.id("dev", "The device, by its id within the Equipment Set.").freeze
      DEVICE_EXAMPLE = { "id" => "eqs_Ab12Cd34Ef56", "device_id" => "dev_Ab12Cd34Ef56" }.freeze
      RESET_KINDS = { "program" => PROGRAM_KIND, "equipment_set" => EQUIPMENT_SET_KIND }.freeze
      CODES = {
        "programs.default_in_use" => "A Program or Equipment Set is the Model's default; a delete must name a " \
                                     "replacement, which becomes the default."
      }.freeze
      PROFILE = SchemaShapes.object({
        "hours" => SchemaShapes.list({ "type" => "number" }, :description => "The value in each hour, 0:00 first."),
        "daily_full_load_hours" => { "type" => %w[number null], "x-unit" => "h",
                                     "description" => "Null for an activity or temperature Schedule." },
        "annual_full_load_hours" => { "type" => %w[number null], "x-unit" => "h",
                                      "description" => "The daily hours on days_per_week × weeks_per_year days." },
        "weekdays" => SchemaShapes.list({ "type" => "string", "enum" => ScheduleProfile::WEEKDAYS },
                                        :description => "The days the profile applies on, Monday first: the first " \
                                                        "days_per_week, or every day for a temperature Schedule.")
      }).freeze

      module_function

      def install(feature)
        COLLECTIONS.each do |collection, kind|
          prefix = "#{FEATURE_ID}.#{collection}"
          example = EXAMPLES.fetch(collection)
          reads(feature, prefix, collection, kind)
          create(feature, prefix, kind)
          update(feature, prefix, kind, example)
          duplicate(feature, prefix, kind, example)
          delete(feature, prefix, kind, example)
        end
        add_device(feature)
        update_device(feature)
        delete_device(feature)
        device_types(feature)
        settings(feature)
        reset_default(feature)
        schedule_profile(feature)
        CODES.each { |code, description| feature.code(code, :description => description) }
      end

      def create(feature, prefix, kind)
        handler = lambda do |request, proposal|
          Operations.create(request, proposal, kind.id, :values => request.params.fetch("values", {}),
                                                        :user_data => request.params["user_data"])
        end
        feature.action("#{prefix}.create", :description => "Create one #{kind.label} with default values.",
                                           :refuses => Refuses::CREATE, :params => Shapes.create(kind),
                                           :result => Shapes::RESULT, :undo_name => "Create #{kind.label}",
                                           :side_effects => "Creates one catalog record.",
                                           :examples => [{}, { "values" => { "name" => "Example #{kind.label}" } }],
                       &handler)
      end

      def update(feature, prefix, kind, example)
        handler = lambda do |request, proposal|
          params = request.params
          Operations.update(request, proposal, kind.id, :id => params.fetch("id"), :values => params.fetch("values"),
                                                        :expected_values => params.fetch("expected_values"))
        end
        feature.action("#{prefix}.update", :description => "Edit one #{kind.label}; changed expected values refuse.",
                                           :refuses => Refuses::EDIT, :params => Shapes.update(kind),
                                           :result => Shapes::RESULT, :undo_name => "Edit #{kind.label}",
                                           :side_effects => "Updates values; metadata stays as stored.",
                                           :examples => [{ "id" => example, "values" => { "name" => "Edited" },
                                                           "expected_values" => { "name" => "Original" } }], &handler)
      end

      def duplicate(feature, prefix, kind, example)
        properties = { "id" => Shapes.id(kind.id_prefix, "The #{kind.label} to copy."),
                       "name" => { "type" => "string", "minLength" => 1,
                                   "description" => "The copy's name; \"<name> (copy)\" when absent." } }
        handler = lambda do |request, proposal|
          Operations.duplicate(request, proposal, kind.id, :id => request.params.fetch("id"),
                                                           :name => request.params["name"])
        end
        feature.action("#{prefix}.duplicate", :description => "Duplicate one #{kind.label} with a new identity.",
                                              :refuses => Refuses::DUPLICATE,
                                              :params => Shapes.object(properties, :optional => ["name"]),
                                              :result => Shapes::RESULT, :undo_name => "Duplicate #{kind.label}",
                                              :side_effects => "Creates one catalog record; Schedules stay shared.",
                                              :examples => [{ "id" => example }], &handler)
      end

      def delete(feature, prefix, kind, example)
        properties = { "id" => Shapes.id(kind.id_prefix, "The #{kind.label} to delete."),
                       "expected_values" => Shapes::EXPECTED_VALUES,
                       "replacement_id" => Shapes.id(kind.id_prefix, "The #{kind.label} every use of the deleted " \
                                                                     "one takes instead. Needed while anything " \
                                                                     "uses it.") }
        staged = [PROGRAM_KIND, EQUIPMENT_SET_KIND].include?(kind.id)
        moved = staged ? ", Zone assignments and Segment settings included" : ""
        handler = lambda do |request, proposal|
          params = request.params
          Operations.delete(request, proposal, kind.id, :id => params.fetch("id"),
                                                        :expected_values => params.fetch("expected_values", {}),
                                                        :replacement_id => params["replacement_id"])
        end
        feature.action("#{prefix}.delete", :description => "Delete one #{kind.label}; remaining uses refuse.",
                                           :refuses => staged ? Refuses::DELETE_STAGED : Refuses::DELETE,
                                           :participants => staged ? [Zones::ExtensionStaging::NAME] : [],
                                           :params => Shapes.object(properties,
                                                                    :optional => %w[expected_values replacement_id]),
                                           :result => Shapes.with_removed_user_data(Shapes::RESULT),
                                           :undo_name => "Delete #{kind.label}",
                                           :side_effects => "A replacement takes every use#{moved}, then the " \
                                                            "record goes, in one step.",
                                           :examples => [{ "id" => example }], &handler)
      end

      def reads(feature, prefix, collection, kind)
        row = row(collection, kind)
        list = Shapes.object({ "records" => Shapes.list(row), "unreadable" => DefinitionLists::UNREADABLE,
                               "next_cursor" => Pages::NEXT_CURSOR, "total" => Pages::TOTAL })
        params = Shapes.object({ "ids" => Shapes.list(Shapes::TEXT).merge("maxItems" => Pages::MAXIMUM_LIMIT,
                                                                          "description" => "Only these record ids."),
                                 "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR },
                               :optional => %w[ids limit cursor])
        feature.query("#{prefix}.list", :description => "One bounded page of #{collection} in id order, with what " \
                                                        "uses each.",
                                        :refuses => Refuses::PAGE + Refuses::USES, :params => params, :result => list,
                                        :examples => [{}, { "limit" => 20 }]) do |request|
          Inventory.list(request, "#{prefix}.list", kind.id)
        end
        all = Shapes.object({ "records" => Shapes.list(row), "unreadable" => DefinitionLists::UNREADABLE })
        feature.query("#{prefix}.all", :response => { "bounded" => false, "prefer" => "#{prefix}.list" },
                                       :description => "Every #{kind.label}, PH-Composer's defaults included.",
                                       :refuses => Refuses::USES, :params => Shapes::NONE, :result => all,
                                       :examples => [{}]) do |request|
          Inventory.all(request, kind.id)
        end
        # The Programs tab reads the three catalogs it edits from the snapshot; Dwellings are read with occupancy.
        feature.snapshot_section(prefix, :query => "#{prefix}.all") unless collection == "dwellings"
      end

      def row(collection, kind)
        view = Shapes.view(kind)
        unless collection == "schedules"
          row = Shapes.with(view, "default" => { "type" => "boolean" }, "use_count" => Shapes::COUNT)
          return row unless collection == "programs"

          gap = Shapes.object({ "load" => Shapes::TEXT, "field" => Shapes::TEXT })
          return Shapes.with(row, "missing" => Shapes.list(gap, :description => "Each value its ProgramType " \
                                                                                "would lack, by load and field, " \
                                                                                "as the export preflight reports " \
                                                                                "it."))
        end

        use = Shapes.object({ "program_id" => Shapes::TEXT, "name" => Shapes::TEXT,
                              "slot" => Shapes.described(Shapes::TEXT, "The load and field, such as " \
                                                                       "people.occupancy_schedule_id.") })
        Shapes.with(view, "uses" => Shapes.list(use), "use_count" => Shapes::COUNT, "profile" => PROFILE)
      end

      def add_device(feature)
        type = { "type" => "string", "enum" => EquipmentTypes::NAMES,
                 "description" => "The honeybee-ph type; equipment_sets.device_types lists each one's fields." }
        values = Shapes.described(Shapes.device_values(:nullable => false),
                                  "The device's values; any not given take the type's defaults.")
        params = Shapes.object({ "id" => SET_ID, "type" => type, "values" => values }, :optional => ["values"])
        handler = lambda do |request, proposal|
          params = request.params
          Operations.add_device(request, proposal, :set_id => params.fetch("id"), :type => params.fetch("type"),
                                                   :values => params.fetch("values", {}))
        end
        feature.action("#{DEVICES}.add_device",
                       :description => "Add one device of a honeybee-ph type, with that type's defaults under the " \
                                       "values given.",
                       :refuses => Refuses::EDIT, :params => params, :result => Shapes::DEVICE_RESULT,
                       :undo_name => "Add Device", :side_effects => "Adds one device to the Equipment Set.",
                       :examples => [{ "id" => DEVICE_EXAMPLE.fetch("id"), "type" => "dishwasher" }], &handler)
      end

      def update_device(feature)
        params = Shapes.object({ "id" => SET_ID, "device_id" => DEVICE_ID,
                                 "values" => Shapes.described(Shapes.device_values(:nullable => true),
                                                              "The values to change; null removes one."),
                                 "expected_values" => Shapes.described(Shapes.device_values(:nullable => true),
                                                                       Shapes::EXPECTED) })
        handler = lambda do |request, proposal|
          params = request.params
          Operations.update_device(request, proposal, :set_id => params.fetch("id"),
                                                      :device_id => params.fetch("device_id"),
                                                      :values => params.fetch("values"),
                                                      :expected_values => params.fetch("expected_values"))
        end
        feature.action("#{DEVICES}.update_device", :description => "Edit one device's values; its type is fixed.",
                                                   :refuses => Refuses::EDIT, :params => params,
                                                   :result => Shapes::DEVICE_RESULT, :undo_name => "Edit Device",
                                                   :side_effects => "Updates one device; its user_data stays.",
                                                   :examples => [DEVICE_EXAMPLE.merge(
                                                     "values" => { "quantity" => 2 },
                                                     "expected_values" => { "quantity" => 1 }
                                                   )], &handler)
      end

      def delete_device(feature)
        params = Shapes.object({ "id" => SET_ID, "device_id" => DEVICE_ID,
                                 "expected_values" => Shapes.described(Shapes.device_values(:nullable => true),
                                                                       Shapes::EXPECTED) },
                               :optional => ["expected_values"])
        handler = lambda do |request, proposal|
          params = request.params
          Operations.delete_device(request, proposal, :set_id => params.fetch("id"),
                                                      :device_id => params.fetch("device_id"),
                                                      :expected_values => params.fetch("expected_values", {}))
        end
        feature.action("#{DEVICES}.delete_device", :description => "Delete one device from its Equipment Set.",
                                                   :refuses => Refuses::EDIT, :params => params,
                                                   :result => Shapes.with_removed_user_data(Shapes::DEVICE_RESULT),
                                                   :undo_name => "Delete Device",
                                                   :side_effects => "Removes one device and its user_data.",
                                                   :examples => [DEVICE_EXAMPLE], &handler)
      end

      def device_types(feature)
        feature.query("#{DEVICES}.device_types",
                      :description => "The fourteen honeybee-ph device types: each one's fields, allowed reference " \
                                      "quantities and energy norms, and a new device's values.",
                      :refuses => [], :params => Shapes::NONE,
                      :result => Shapes.object({ "types" => Shapes.list(Shapes::OBJECT) }),
                      :examples => [{}]) { |_request| { "types" => EquipmentTypes.catalog } }
      end

      def settings(feature)
        values = Shapes.object(Settings::FIELDS.keys.to_h { |key| [key, Shapes::TEXT] })
        partial = values.merge("required" => [])
        feature.query("#{FEATURE_ID}.settings.get",
                      :description => "The Model's default Program and default Equipment Set, PH-Composer's own " \
                                      "until another is chosen.",
                      :refuses => Refuses::READ, :params => Shapes::NONE, :result => values,
                      :examples => [{}]) { |request| Settings.read(request.model) }
        handler = lambda do |request, proposal|
          Operations.update_settings(request, proposal, :values => request.params.fetch("values"),
                                                        :expected_values => request.params.fetch("expected_values"))
        end
        example = { "values" => { "default_program_id" => "pgm_Ab12Cd34Ef56" },
                    "expected_values" => { "default_program_id" => DefaultProgram::PROGRAM_ID } }
        feature.action("#{FEATURE_ID}.settings.update",
                       :description => "Choose the Model's default Program or Equipment Set; each update guards only " \
                                       "the defaults it names.",
                       :refuses => Refuses::EDIT,
                       :params => Shapes.object({ "values" => Shapes.described(partial, "The defaults to change, at " \
                                                                                        "least one."),
                                                  "expected_values" => Shapes.described(partial, "The defaults as " \
                                                                                                 "last read.") }),
                       :result => values, :undo_name => "Change Programs Defaults",
                       :side_effects => "Stores the defaults in this SKP, and stores the residential default it " \
                                        "displaces.",
                       :examples => [example], &handler)
      end

      def reset_default(feature)
        handler = lambda do |request, proposal|
          Operations.reset_default(request, proposal, RESET_KINDS.fetch(request.params.fetch("kind")),
                                   :expected_values => request.params.fetch("expected_values", {}))
        end
        feature.action("#{FEATURE_ID}.reset_default",
                       :description => "Rewrite the residential default Program or the default Equipment Set from " \
                                       "PH-Composer's definition, writing back any default Schedule it names that " \
                                       "is gone.",
                       :refuses => Refuses::EDIT,
                       :params => Shapes.object({ "kind" => { "type" => "string", "enum" => RESET_KINDS.keys,
                                                              "description" => "Which default to reset." },
                                                  "expected_values" => Shapes.described(Shapes::OBJECT,
                                                                                        Shapes::EXPECTED) },
                                                :optional => ["expected_values"]),
                       :result => Shapes.with_removed_user_data(Shapes::RESULT),
                       :undo_name => "Reset to PH-Composer Default",
                       :side_effects => "Replaces the record's values; its user_data stays, and a device the " \
                                        "definition lacks goes with its map.",
                       :examples => [{ "kind" => "program" }, { "kind" => "equipment_set" }], &handler)
      end

      def schedule_profile(feature)
        values = Shapes.create(Schedule::KIND).dig("properties", "values")
        feature.query("#{FEATURE_ID}.schedules.profile",
                      :description => "The 24-hour profile and full-load hours of Schedule values, stored or not.",
                      :refuses => %w[validation.failed],
                      :params => Shapes.object({ "values" => Shapes.described(values, "A Schedule's values; a " \
                                                                                      "missing one takes its " \
                                                                                      "default.") }),
                      :result => PROFILE,
                      :examples => [{ "values" => { "type" => "fractional", "start_h" => 7,
                                                    "end_h" => 18 } }]) do |request|
          profile(request.params.fetch("values"))
        end
      end

      def profile(values)
        values = Schedule.defaults(values.merge("name" => values.fetch("name", "Profile")))
        problems = Schedule::KIND.problems({ "id" => "sch_AAAAAAAAAAAA", "schema_version" => 1 }.merge(values))
        raise CodedError.new("validation.failed", "The Schedule is not valid: #{problems.first}.") if problems.any?

        ScheduleProfile.call(values)
      end
    end
  end
end
