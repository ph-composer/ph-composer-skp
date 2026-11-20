# frozen_string_literal: true

module PhComposer
  module Zones
    module Options
      # One Building Segment's settings and the Segments the Zone views make (context/EXTENSIBILITY.md,
      # "Building Segment settings"). Settings live on the Segment as structured extensions, one namespace per
      # section, registered by each section's feature. Zones stages every namespace itself, so no section owner
      # writes the Segment record: Save is one proposal and one Undo step, and a section's owner adds its own
      # side effects through the `segment_settings_saved` transition. Writing a payload touches the Segment
      # alone (a Zone's evidence holds the Segment's values, not its settings), so a locked member Zone never
      # blocks it; a rename or a new default still rewrites its members as any option edit does.
      module SegmentSettings
        SAVE = "#{FEATURE_ID}.save_segment_settings"
        CREATE = "#{FEATURE_ID}.create_segment"
        TRANSITION = "#{FEATURE_ID}.segment_settings_saved"
        DEFAULT_NAME = "Building Segment"

        module_function

        # Saves the dialog: the General values (name, colour, whether new Zones join it) and a payload per
        # namespace, each guarded by what the dialog read. The General values are staged first, so the payloads
        # are written onto the record as the proposal leaves it.
        def save(request, proposal, id:, values:, expected_values:, default:, expected_default_segment_id:,
                 extension_payloads:, expected_extension_data:)
          record = request.engine.find(SEGMENT_KIND, id)
          current_default = Options.settings(request.engine)&.fetch("default_segment_id")
          unless record.slice("name", "colour") == expected_values && current_default == expected_default_segment_id
            Options.refuse("target.changed", "The Building Segment changed since its settings opened")
          end
          if !default && current_default == id
            Options.refuse("params.invalid", "New Zones join the default Building Segment; make another Segment " \
                                             "the default")
          end
          default_id = default ? id : current_default
          general(request, proposal, id, values, default_id) if general_changed?(record, values, default_id,
                                                                                 current_default)
          namespaces = stage_extensions(request, proposal, SEGMENT_KIND, id, extension_payloads,
                                        expected_extension_data)
          request.contribute_transition(TRANSITION, { "building_segment_id" => id, "namespaces" => namespaces })
          { "id" => id, "namespaces" => namespaces }
        end

        def general_changed?(record, values, default_id, current_default)
          default_id != current_default || record.fetch("name") != values.fetch("name").strip ||
            record.fetch("colour") != values.fetch("colour").upcase
        end

        # The General values through the collection's own management, so names stay unique, a default is
        # kept and every member's evidence follows a rename in the same step.
        def general(request, proposal, id, values, default_id)
          params = Commands.draft(request, "building_segment")
          params.fetch(:options).find { |row| row.fetch("id") == id }.merge!(values.slice("name", "colour"))
          params[:default_segment_id] = default_id
          Options.manage(request, proposal, **params)
        end

        # The one staging route for settings on a catalog record: `payloads` by namespace, each checked by its
        # installed validator (Records::Extension#problems) and written in this proposal, guarded by the
        # record's `extension_data` as the caller read it. Answers the namespaces whose payload changed, sorted.
        # A later stage exposes this route to Programs as the `stage_extension` participant.
        def stage_extensions(request, proposal, kind_id, id, payloads, expected_extension_data)
          return [] if payloads.empty?

          before = request.engine.find(kind_id, id, :change_set => proposal.record_changes)
          update = { "reference" => { "kind" => kind_id, "id" => id },
                     "expected_metadata" => { "user_data" => before.fetch("user_data", {}),
                                              "extension_data" => expected_extension_data },
                     "extension_payloads" => payloads }
          request.engine.propose_metadata_update(kind_id, id, proposal, update)
          after = request.engine.find(kind_id, id, :change_set => proposal.record_changes)
          payloads.keys.sort.reject do |namespace|
            before.dig("extension_data", namespace) == after.dig("extension_data", namespace)
          end
        end

        # A new Building Segment under the first free default name ("Building Segment 2" beside one other),
        # with `targets` moved into it, as one Undo step.
        def create(request, proposal, colour:, targets:)
          name = free_name(request.engine)
          id = Commands.create(request, proposal, "building_segment", { "name" => name, "colour" => colour })
                       .fetch("id")
          zone_ids = Selection.assign(request, proposal, targets) { |before| before.merge("building_segment_id" => id) }
          { "id" => id, "name" => name, "zone_ids" => zone_ids }
        end

        def free_name(engine)
          taken = Options.records(engine, SEGMENT_KIND).map { |row| Options.name_key(row.fetch("name")) }
          number = taken.length + 1
          number += 1 while taken.include?(Options.name_key("#{DEFAULT_NAME} #{number}"))
          "#{DEFAULT_NAME} #{number}"
        end
      end
    end
  end
end

module PhComposer
  module Zones
    module Options
      # What SegmentSettings registers: Save and New Building Segment.
      module SegmentSettingsRegistration
        SEGMENT_ID = SchemaShapes.id("bsg", "The Building Segment.").freeze
        VALUES = Shapes.object({ "name" => NAME, "colour" => COLOUR }).freeze
        REFUSALS = (Registration::REFUSALS + %w[extension.unavailable extension.migration_required
                                                extension.schema_unsupported]).uniq.freeze
        SAVE_PARAMS = Shapes.object({
          "id" => SEGMENT_ID,
          "values" => Shapes.described(VALUES, "The name and colour to save."),
          "expected_values" => Shapes.described(VALUES, "The name and colour the dialog read; a change refuses."),
          "default" => { "type" => "boolean",
                         "description" => "New Zones join this Segment. True makes it the default; false on the " \
                                          "default refuses, because the default moves only to another Segment." },
          "expected_default_segment_id" => SchemaShapes.id("bsg", "The default Segment the dialog read; a change " \
                                                                  "refuses."),
          "extension_payloads" => { "type" => "object", "additionalProperties" => { "type" => "object" },
                                    "description" => "Each settings section's payload by its namespace, checked " \
                                                     "by that namespace's installed validator. A namespace left " \
                                                     "out is kept as stored." },
          "expected_extension_data" => { "type" => "object",
                                         "description" => "The Segment's extension_data as the dialog read it; a " \
                                                          "change refuses." }
        }).freeze
        SAVE_RESULT = Shapes.object({
          "id" => Shapes::ID,
          "namespaces" => Shapes.list({ "type" => "string" },
                                      :description => "The namespaces whose payload changed, sorted.")
        }).freeze
        CREATE_PARAMS = Shapes.object({
          "colour" => Shapes.described(COLOUR, "The new Segment's colour."),
          "targets" => Shapes.list(SelectionRegistration::TARGET,
                                   :description => "Zone occurrences to move into the new Segment, each with the " \
                                                   "values last read; a change refuses. Empty makes an empty " \
                                                   "Segment.")
        }, :optional => ["targets"]).freeze
        CREATE_RESULT = Shapes.object({ "id" => Shapes::ID, "name" => NAME,
                                        "zone_ids" => Shapes.list(Shapes::ID) }).freeze
        EXAMPLE_ID = "bsg_Ab12Cd34Ef56"

        module_function

        def install(feature)
          feature.action(SegmentSettings::SAVE,
                         :description => "Save one Building Segment's settings dialog: its name, colour and " \
                                         "default, and a payload per settings namespace, in one Undo step.",
                         :params => SAVE_PARAMS, :result => SAVE_RESULT, :refuses => REFUSALS,
                         :transitions => [SegmentSettings::TRANSITION],
                         :undo_name => "Change Building Segment Settings",
                         :side_effects => "Writes the Segment's values and settings; a rename or a new default " \
                                          "also rewrites each member Zone's evidence. Every contributor to " \
                                          "#{SegmentSettings::TRANSITION} adds its own changes in the same step.",
                         :examples => [save_example]) do |request, proposal|
            values = request.params
            SegmentSettings.save(request, proposal,
                                 :id => values.fetch("id"), :values => values.fetch("values"),
                                 :expected_values => values.fetch("expected_values"),
                                 :default => values.fetch("default"),
                                 :expected_default_segment_id => values.fetch("expected_default_segment_id"),
                                 :extension_payloads => values.fetch("extension_payloads"),
                                 :expected_extension_data => values.fetch("expected_extension_data"))
          end
          feature.action(SegmentSettings::CREATE,
                         :description => "Make a Building Segment under the first free default name and move " \
                                         "the named Zone occurrences into it, in one Undo step.",
                         :params => CREATE_PARAMS, :result => CREATE_RESULT, :refuses => Registration::REFUSALS,
                         :undo_name => "New Building Segment",
                         :side_effects => "Creates one Segment and updates each moved Zone and its membership " \
                                          "stamps.",
                         :examples => [{ "colour" => "#1F7478" }]) do |request, proposal|
            SegmentSettings.create(request, proposal, :colour => request.params.fetch("colour"),
                                                      :targets => request.params.fetch("targets", []))
          end
        end

        def save_example
          values = { "name" => "House", "colour" => "#1F7478" }
          { "id" => EXAMPLE_ID, "values" => values, "expected_values" => values, "default" => true,
            "expected_default_segment_id" => EXAMPLE_ID, "extension_payloads" => {},
            "expected_extension_data" => {} }
        end
      end
    end
  end
end
