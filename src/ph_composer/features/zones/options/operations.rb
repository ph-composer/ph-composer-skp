# frozen_string_literal: true

module PhComposer
  module Zones
    module Options
      module_function

      # The Zone record field that names an option of `collection`.
      def zone_field(collection)
        collection == "building_segment" ? "building_segment_id" : "level_id"
      end

      def all(request)
        inventory = Inventory.rows(request.model)
        lists = KINDS.to_h do |collection, kind|
          rows = records(request.engine, kind.id).map do |record|
            request.engine.view(kind.id, record).slice("id", "schema_version", "values", "user_data", "extension_data")
                   .merge("usage" => usage(inventory, collection, record.fetch("id")))
          end
          [collection == "level" ? "levels" : "building_segments", rows]
        end
        lists.merge("default_segment_id" => settings(request.engine)&.fetch("default_segment_id"),
                    "adoption" => Adoption.preview(request, inventory))
      end

      # How many live Zones use option `id`, and how many Zones that are gone but recoverable from their
      # members' stamps do.
      def usage(inventory, collection, id)
        field = zone_field(collection)
        live_ids = inventory.select { |row| row.fetch(:zone) }.map { |row| row.fetch(:record).fetch("id") }
        matching = inventory.select { |row| row.fetch(:record)[field] == id }
        remembered = matching.reject { |row| row.fetch(:zone) }.map { |row| row.fetch(:record).fetch("zone_id") }.uniq
        { "live" => matching.count { |row| row.fetch(:zone) },
          "recoverable" => remembered.count { |zone_id| !live_ids.include?(zone_id) } }
      end

      def choice_rows(engine, collection)
        records(engine, KINDS.fetch(collection).id).map { |row| row.slice("id", "name", "colour") }
      end

      def set_settings(request, proposal, default_id)
        request.engine.find(SEGMENT_KIND, default_id, :change_set => proposal.record_changes)
        before = settings(request.engine)
        if before
          request.engine.propose_update(SETTINGS_KIND, SETTINGS_ID, proposal,
                                        :values => { "default_segment_id" => default_id })
        else
          after = { "id" => SETTINGS_ID, "schema_version" => 1, "default_segment_id" => default_id,
                    "source_model_id" => Records::Identity.derived("zmo", "model" => request.model.guid) }
          refuse("validation.failed", "Invalid Zone option settings") unless SETTINGS.problems(after).empty?
          proposal.put(SETTINGS_KIND, :before => nil, :after => after)
        end
      end

      def ensure_default(request, proposal)
        current = settings(request.engine)
        return request.engine.find(SEGMENT_KIND, current.fetch("default_segment_id")) if current

        if Adoption.preview(request, Inventory.rows(request.model)).fetch("required")
          refuse("zone.options_adoption_required", "Adopt existing Zone choices before making another Zone")
        end

        id = create_choice(request, proposal, "building_segment", Occurrences.default_segment(request.model), "#1F7478")
        set_settings(request, proposal, id)
        request.engine.find(SEGMENT_KIND, id, :change_set => proposal.record_changes)
      end

      def create_choice(request, proposal, collection, name, colour, portable: nil)
        kind = KINDS.fetch(collection)
        values = { "name" => name.strip, "colour" => colour.upcase }
        if collection == "building_segment"
          values["export_identifier"] = portable&.fetch("export_identifier", nil) ||
                                        export_identifier("#{request.model.guid}:#{request.revision}:#{name}")
        end
        request.engine.propose_create(kind.id, proposal, :values => values,
                                                         :user_data => portable&.fetch("user_data", nil))
      end

      def copy_extensions(request, proposal, kind, portable, id, typed_mappings)
        payload = portable.fetch("extension_data", {})
        return if payload.empty?

        Records::Extension.check_copy_rules!(payload, request.registry.catalog, kind.label, portable.fetch("id"))
        remapped = DeepCopy.call(payload)
        remapped.each_value do |envelope|
          envelope.fetch("references", []).each do |reference|
            mapping = typed_mappings.fetch(reference.fetch("target_kind"), {})
            envelope["payload"] = Records::Extension.remap(envelope.fetch("payload"), [reference], mapping)
          end
        end
        projected = request.engine.projected(proposal.record_changes, :writable_kinds => [],
                                                                      :refusal_code => "validation.failed")
        validated = Records::Extension.copy_data(remapped, request.registry.catalog, kind.label,
                                                 portable.fetch("id"), {}, :engine => projected)
        after = proposal.find(kind.id, id).after.merge("extension_data" => validated)
        problems = kind.problems(after)
        refuse("validation.failed", problems.first) unless problems.empty?
        proposal.restage(kind.id, id, :after => after)
      end

      # Replaces one option collection as the dialog left it. The order is the commit order: guards on the
      # state the dialog read, the staged options, the replacement for each removed one, the default
      # Building Segment, the Zone rewrites, and last the deletions the rewrites leave unreferenced.
      def manage(request, proposal, collection:, options:, expected_options:, default_segment_id:,
                 expected_default_segment_id:, replacements:)
        inventory = Inventory.rows(request.model)
        if Adoption.preview(request, inventory).fetch("required")
          refuse("zone.options_adoption_required", "Adopt legacy or copied choices before managing options")
        end
        before = choice_rows(request.engine, collection)
        unless before.sort_by { |row| row.fetch("id") } == expected_options.sort_by { |row| row.fetch("id") } &&
               settings(request.engine)&.fetch("default_segment_id") == expected_default_segment_id
          refuse("target.changed", "Zone options changed since the dialog opened")
        end
        kind = KINDS.fetch(collection)
        ids = options.map { |row| row.fetch("id") }
        refuse("params.invalid", "An option appears more than once") unless ids.uniq == ids
        created = stage_options(request, proposal, collection, options)
        final_ids = ids.map { |id| created.fetch(id, id) }
        final = final_ids.map { |id| request.engine.find(kind.id, id, :change_set => proposal.record_changes) }
        validate_collection!(final, collection)
        removed = before.map { |row| row.fetch("id") } - final_ids
        refuse("params.invalid", "Replacement names an option that remains") unless (replacements.keys - removed).empty?
        mapping = replacement_mapping(inventory, collection, removed, replacements, created, final_ids)
        stage_default_segment(request, proposal, collection, created.fetch(default_segment_id, default_segment_id),
                              expected_default_segment_id, final_ids)
        reference_plan = rewrite(request, proposal, collection, mapping, inventory)
        removed.each do |id|
          request.engine.propose_delete(kind.id, id, proposal, :reference_plan => reference_plan)
        end
        { "created_ids" => created, "replacement_ids" => mapping }
      end

      # Each removed option id and the final option its users move to, or nil. A used option needs an
      # explicit entry in `replacements`; a used Level may map to nil, which clears it, but a used Building
      # Segment needs a final option. An unused option maps to its replacement or nil.
      def replacement_mapping(inventory, collection, removed, replacements, created, final_ids)
        removed.to_h do |id|
          used = usage(inventory, collection, id).values.any?(&:positive?)
          refuse("reference.in_use", "Choose a replacement for the used option") if used && !replacements.key?(id)

          target = created.fetch(replacements[id], replacements[id])
          if target && !final_ids.include?(target)
            refuse("reference.invalid", "Choose an option in the final collection")
          end
          if collection == "building_segment" && used && target.nil?
            refuse("reference.invalid", "Building Segment requires a replacement")
          end
          [id, target]
        end
      end

      # The Model's default Building Segment must remain in the final collection; managing Levels leaves it.
      def stage_default_segment(request, proposal, collection, default_id, expected_default_id, final_ids)
        if collection == "building_segment"
          refuse("reference.invalid", "Choose the default Building Segment") unless final_ids.include?(default_id)
          set_settings(request, proposal, default_id) unless default_id == expected_default_id
        elsif default_id != expected_default_id
          refuse("params.invalid", "Level management cannot change the default Segment")
        end
      end

      def stage_options(request, proposal, collection, options)
        kind = KINDS.fetch(collection)
        created = {}
        options.each do |row|
          id = row.fetch("id")
          if id.start_with?("new:")
            # A single-option create may carry the new option's user_data, written with the record.
            portable = row.key?("user_data") ? { "user_data" => row.fetch("user_data") } : nil
            created[id] = create_choice(request, proposal, collection, row.fetch("name"), row.fetch("colour"),
                                        :portable => portable)
          else
            values = { "name" => row.fetch("name").strip, "colour" => row.fetch("colour").upcase }
            request.engine.propose_update(kind.id, id, proposal, :values => values)
          end
        end
        created
      end

      def rewrite(request, proposal, collection, mapping, inventory = Inventory.rows(request.model))
        field = zone_field(collection)
        writes = []
        entries = []
        inventory.each do |row|
          before = row.fetch(:record)
          next unless before.fetch("schema_version") == 2

          after = DeepCopy.call(before)
          after[field] = mapping.fetch(before[field], before[field])
          after["choice_evidence"] = evidence(request.engine, after, proposal)
          next if after == before

          add_rewrite(row, after, writes)
          record = row.fetch(:zone) ? after : after.merge("id" => after.fetch("zone_id"))
          entries << Records::ReferenceEntry.new(:kind => row.fetch(:zone) ? REFERENCE_KIND : STAMP_KIND,
                                                 :key => row.fetch(:path), :record => record)
        end
        add_writes(proposal, writes)
        Records::ReferencePlan.new(:entries => entries)
      end

      # Queues one record write as `[inventory row, record after]`. Shared storage can reach one
      # dictionary through several rows, so a second write to it must agree with the first.
      def add_rewrite(row, after, writes)
        refuse("target.locked", "A Zone or recoverable member is locked") if row.fetch(:locked)
        written = ->(candidate) { [candidate.fetch(:entity).object_id, candidate.fetch(:store).dictionary] }
        previous = writes.find { |candidate, _| written.call(candidate) == written.call(row) }
        if previous
          refuse("zone.options_conflict", "Shared storage has conflicting choice evidence") if previous.last != after
        else
          writes << [row, after]
        end
      end

      def add_writes(proposal, writes)
        return if writes.empty?

        proposal.add_step(RewriteStep.new(writes),
                          :scopes => writes.map { |row, _| Operations::EntityScope.new(row.fetch(:path)[0...-1]) })
      end

      def adapt_values(engine, before, values)
        return values if values.key?("building_segment_id")

        if before.fetch("schema_version") == 1
          unless values.values_at("building_segment", "level") == before.values_at("building_segment", "level")
            refuse("zone.options_adoption_required", "Adopt this Model's Zone options before changing categories")
          end
          return values
        end

        segment_id = existing_name(engine, "building_segment", values.fetch("building_segment"))
        level_id = values["level"] && existing_name(engine, "level", values.fetch("level"))
        values.reject { |key, _| %w[building_segment level].include?(key) }
              .merge("building_segment_id" => segment_id, "level_id" => level_id)
      end

      def existing_name(engine, collection, name)
        wanted = name_key(name)
        matches = records(engine, KINDS.fetch(collection).id).select { |row| name_key(row.fetch("name")) == wanted }
        refuse("reference.invalid", "Choose an existing #{collection.tr('_', ' ')} option") unless matches.length == 1
        matches.first.fetch("id")
      end
    end
  end
end
