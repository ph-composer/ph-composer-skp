# frozen_string_literal: true

module PhComposer
  module Zones
    module Faces
      # The Face handlers the declarations register: the reads, Classify, Suggest and Reverse. The
      # Attached zone writes are in attached_zone_operations.rb. Each only reads and proposes; the
      # dispatcher owns the native operation.

      module_function

      # Refusals that leave a Face unwritable where it sits; the user's remedy is on the Group.
      UNWRITABLE_CODES = %w[target.shared_definition target.locked].freeze

      # What the palette shows: what the tool is set to, and what it may be set to. The words each
      # value is shown by belong to whichever surface shows it; the stored honeybee string is the
      # contract (context/UBIQUITOUS_LANGUAGE.md).
      def tool_state(session)
        tool = classify_tool(session)
        {
          "active" => tool.active?,
          "palette" => tool.palette.each_with_object({}) { |(field, intent), chosen| chosen[field] = intent["value"] },
          "face_types" => ASSIGNABLE_FACE_TYPES,
          "boundary_conditions" => PALETTE_BOUNDARIES,
          "gesture_face_limit" => gesture_face_limit
        }
      end

      # Locate changes the camera and the viewport's outline, and Select the selection and the camera,
      # and nothing else, which is why they are view commands rather than actions: registering one as an
      # action would manufacture an Undo entry for a read (context/AGENT_INTERFACE.md, "explicit
      # selection, reveal and camera operations").
      def locate(request, faces:)
        found = Locate.call(request.session, faces)
        { "found" => found.length, "missing" => faces.length - found.length }
      end

      def select(request, faces:)
        found = Locate.select(request.session, faces)
        { "found" => found.length, "missing" => faces.length - found.length }
      end

      # One page of Face occurrences in root-to-Face path order, filtered by Zone id, Zone path or Face
      # id. The walk covers the Model once; only the page's rows are measured and resolved, and with
      # `fields` a row is its reference and the named values, with no geometry or derived state.
      def list(request)
        params = request.params
        index = Zones::Index.new(request.model)
        occurrences = Zones::Occurrences.zones(request.model, :index => index).flat_map do |zone|
          next [] if params.key?("zone_ids") && !params["zone_ids"].include?(zone.record.fetch("id"))
          next [] if params.key?("zone_paths") && !params["zone_paths"].include?(zone.path)

          Zones::Occurrences.faces(zone, :index => index)
        end
        if params.key?("ids")
          occurrences = occurrences.select do |face|
            params["ids"].include?(FACE_STORE.read(face.entity)&.fetch("id", nil))
          end
        end
        occurrences = occurrences.sort_by { |face| face.zone.path + face.path }
        page, next_cursor = Pages.slice(request, "#{PREFIX}.list", occurrences,
                                        :key => ->(face) { face.zone.path + face.path })
        rows = page.map do |face|
          params.key?("fields") ? projected_view(face, params["fields"]) : face_view(request, face, :index => index)
        end
        { "faces" => rows, "units" => { "area_m2" => "m2" }, "next_cursor" => next_cursor,
          "total" => occurrences.length }
      end

      # Every Face, whole: the panel's projection. Scripts page `list` instead. One walk for the whole
      # read: without the index this resolved every Surface Face's counterpart separately, which walked
      # the Model again for each one and made the read quadratic in Faces.
      def all(request)
        index = Zones::Index.new(request.model)
        rows = Zones::Occurrences.zones(request.model, :index => index).flat_map do |zone|
          Zones::Occurrences.faces(zone, :index => index)
                            .map { |face| face_view(request, face, :index => index) }
        end
        { "faces" => rows, "units" => { "area_m2" => "m2" }, "assembly_usage" => AssemblyAssignment.usage(rows) }
      end

      # The narrow host read: one row per path naming a Zone Face, by the pick rule, with the refusal a
      # write to it would meet from its path. It scans only the collections along each path, never the
      # whole Model, so a viewport tool may call it on a pointer move. A hosting
      # feature reads this instead of `all`, which computes suggestions, adjacency and Assembly state
      # for every Face. Zone state needs every Zone occurrence, so it stays with the Zone reads.
      def host_context(request, paths:)
        children = Zones::ChildLookup.new
        rows = paths.filter_map do |path|
          occurrence = Zones::Occurrences.occurrence_at(request.model, path, :children => children)
          next unless occurrence

          record = FACE_STORE.read(occurrence.entity)
          Schema.validate!(record) if record
          { "path" => path, "reference" => occurrence.reference(record&.fetch("id", nil)),
            "values" => record ? Schema.values(record) : {},
            "write_refusal" => Zones::Occurrences.write_refusal(occurrence, :children => children) }
        end
        { "faces" => rows }
      end

      def projected_view(occurrence, fields)
        record = FACE_STORE.read(occurrence.entity)
        Schema.validate!(record) if record
        { "reference" => occurrence.reference(record&.fetch("id", nil)),
          "values" => record ? Schema.values(record).slice(*fields) : {} }
      end

      # The user_data and installed extension payloads of recorded Faces, guarded by the two maps as
      # last read, in one step (context/CONTRACTS.md, "Records and extension data"). A Face with no record
      # has no metadata to update and refuses as resolving it does.
      def update_metadata(request, proposal, updates:)
        catalog = request.registry.catalog
        rows = Records::Metadata.distinct_updates(updates).map do |update|
          reference = update.fetch("reference")
          before = FACE_STORE.read(Zones::Occurrences.resolve_face(request.model, reference, :mutable => true).entity)
          after = Records::Metadata.planned(request.engine, catalog, before, update, "Face")
          Schema.validate!(after)
          { "reference" => reference, "before" => before, "after" => after, "change" => "updated", "stamp" => nil }
        end
        changed = rows.reject { |row| row.fetch("before") == row.fetch("after") }
        unless changed.empty?
          scopes = changed.map { |row| row.fetch("reference").fetch("zone_path")[0...-1] }.uniq.map do |path|
            Operations::EntityScope.new(path)
          end
          proposal.add_step(ClassifyStep.new(:updates => changed), :scopes => scopes)
        end
        { "updates" => rows.map do |row|
          { "reference" => row.fetch("reference"),
            "extension_status" => Records::Metadata.status_map(row.fetch("after"), catalog) }
        end }
      end

      # One gesture, one step, all or nothing. Targets are deduplicated by occurrence before anything
      # is resolved, so an over-limit gesture refuses without walking the Model once per Face.
      def classify(request, proposal, faces:, intent:, expected_values: {})
        plan_classification(request, proposal, faces, intent, expected_values)
      end

      def plan_classification(request, proposal, faces, intent, expected)
        validate_intent!(intent)
        references = deduplicate(faces)
        check_limit!(references.length)

        # One walk for the whole gesture. Nothing here changes the Model: the proposal is applied
        # afterwards, by steps that resolve against the live Model themselves.
        index = Zones::Index.new(request.model)
        targets = references.map do |reference|
          occurrence = Zones::Occurrences.resolve_face(
            request.model, reference, :mutable => true, :allow_unassigned => reference["entity_id"].nil?,
                                      :index => index
          )
          record = FACE_STORE.read(occurrence.entity)
          check_expected!(record, expected)
          [occurrence, record]
        end
        retirements = plan_retirements(request, targets, intent, :index => index)
        check_limit!((targets.map { |occurrence, _record| Zones::Occurrences.key(occurrence.reference) } +
                      retirements.keys).uniq.length)

        updates = classify_updates(request, targets, retirements, intent)
        updates.concat(retirement_only_updates(targets, retirements))
        return { "face_ids" => [] } if updates.empty?

        scopes = updates.map do |update|
          Operations::EntityScope.new(update.fetch("reference").fetch("zone_path")[0...-1])
        end
        proposal.add_step(ClassifyStep.new(:updates => updates), :scopes => scopes)
        { "face_ids" => updates.reject { |update| update.fetch("change") == "retired" }
                               .map { |update| update.fetch("after").fetch("id") } }
      end

      # `skip_unwritable` is Make Zone's suggestion: a Face in a shared or locked child Group stays
      # unclassified, visible in validation, rather than refusing the Zone it is being made in.
      def auto_classify(request, proposal, zone:, skip_unwritable: false)
        # One walk for the whole batch, so the Zone it resolves is the Zone the index walked and the
        # Faces come back from that same walk.
        index = Zones::Index.new(request.model)
        zone = Zones::Occurrences.resolve_zone(request.model, zone, :mutable => true, :index => index)
        stamp = Zones::Schema.stamp(zone.record)
        # No gesture ceiling here: Auto-classify is a separate named batch over one Zone the user
        # already owns, not a pointer gesture whose target set the user cannot see.
        unrecorded = Zones::Occurrences.faces(zone, :index => index)
                                       .reject { |occurrence| FACE_STORE.read(occurrence.entity) }
        # Each target resolves for mutation now, so a Face in a shared or locked Group refuses here,
        # with its instruction, rather than failing when the step applies.
        unrecorded = unrecorded.select do |occurrence|
          Zones::Occurrences.resolve_face(request.model, occurrence.reference,
                                          :mutable => true, :allow_unassigned => true, :index => index)
          true
        rescue CodedError => error
          raise unless skip_unwritable && UNWRITABLE_CODES.include?(error.code)

          false
        end
        updates = unrecorded.map do |occurrence|
          suggested = Geometry.suggested_values(occurrence, :settings => Settings.read(request.model))
          record = new_record(request, occurrence).merge(suggested)
          { "reference" => occurrence.reference, "before" => nil, "after" => Schema.validate!(record),
            "stamp" => stamp, "change" => "created" }
        end
        unless updates.empty?
          scopes = [Operations::EntityScope.new(zone.path[0...-1])]
          proposal.add_step(ClassifyStep.new(:updates => updates), :scopes => scopes)
        end
        { "classified" => updates.length,
          "kept" => Zones::Occurrences.faces(zone, :index => index).length - updates.length }
      end

      # The one geometry repair this feature owns. The record survives untouched; the changed normal
      # is what makes any Surface pair read stale on the next reconciliation.
      def reverse(request, proposal, face:)
        reference = face
        Zones::Occurrences.resolve_face(request.model, reference, :mutable => true, :allow_unassigned => true)
        scope = Operations::EntityScope.new(reference.fetch("zone_path")[0...-1])
        proposal.add_step(ReverseFaceStep.new(:reference => reference), :scopes => [scope])
        {}
      end

      # The Faces this delete rewrites, as they will stand, so the engine's reference check reads the
      # reassignment rather than the Faces it is about to replace.
      def reassignment_plan(updates)
        entries = updates.map do |update|
          reference = update.fetch("reference")
          Records::ReferenceEntry.new(:kind => REFERENCE_KIND,
                                      :key => reference.fetch("zone_path") + reference.fetch("entity_path"),
                                      :record => update.fetch("after"))
        end
        Records::ReferencePlan.new(:entries => entries)
      end

      # What the user can do about each kind of Face a reassigning write (the Attached zone delete,
      # Assembly assignment) cannot reach. A Face outside every Zone has no reason code of its own; one
      # inside a Zone carries the code its resolution refused.
      STRANDED_ROUTES = {
        "outside_zone" => "Restore its Zone, or remove it",
        "target.shared_definition" => "open its shared Group with Edit Group and close it, or explode its component",
        "target.locked" => "unlock its Group or Zone"
      }.freeze

      def face_view(request, occurrence, index:)
        record = FACE_STORE.read(occurrence.entity)
        Schema.validate!(record) if record
        id = record&.fetch("id", nil)
        view = {
          "reference" => occurrence.reference(id), "zone_name" => occurrence.zone.record.fetch("name"),
          "area_m2" => Geometry.area_m2(occurrence), "values" => record ? Schema.values(record) : {},
          "user_data" => record ? DeepCopy.call(record.fetch("user_data", {})) : {},
          "extension_data" => record ? DeepCopy.call(record.fetch("extension_data", {})) : {},
          "extension_status" => record ? Records::Metadata.status_map(record, request.registry.catalog) : {},
          "suggested" => Geometry.suggested_values(occurrence, :settings => Settings.read(request.model)),
          "attached_zone_state" => AttachedZone.reference_state(request.engine, record),
          "adjacency_state" => Zones::Adjacency.state(request.model, occurrence, record, :index => index),
          "assembly_state" => AssemblyAssignment.state(request, record),
          "findings" => AssemblyAssignment.findings(request, occurrence, record, index)
        }
        view.merge("state" => row_state(view))
      end

      # The three words every surface that shows a Face uses, the same ones a Colour-by legend row
      # carries: no record at all, a record that cannot be exported as it stands, or a complete one.
      # Derived here and never in a view, so no screen coins a fourth word. It judges the whole record,
      # so it can be stricter than a legend row (context/EXTENSIBILITY.md, "Colour-by modes").
      def row_state(view)
        values = view.fetch("values")
        return "unclassified" if values.empty?

        incomplete = values["face_type"].nil? || values["boundary_condition"].nil? ||
                     (view["attached_zone_state"] && view["attached_zone_state"] != "resolved") ||
                     (view["adjacency_state"] && view["adjacency_state"] != "current") ||
                     %w[dangling invalid].include?(view["assembly_state"])
        incomplete ? "incomplete" : "classified"
      end

      def deduplicate(references)
        references.uniq { |reference| Zones::Occurrences.key(reference) }
      end

      # The gesture ceiling. Public with check_expected!, new_record and reassignment_plan because
      # Assembly assignment (assembly_assignment.rb) applies the same rules to its own Face gesture.
      def check_limit!(count)
        limit = gesture_face_limit
        return if count <= limit

        raise CodedError.new("gesture.too_large",
                             "One gesture affects at most #{limit} Faces; this one affects #{count}.")
      end

      def retiring?(record, intent)
        boundary = intent["boundary_condition"]
        record && record["boundary_condition"] == "Surface" && boundary &&
          !(boundary.fetch("mode") == "keep" ||
            (boundary.fetch("mode") == "set" && boundary["value"] == "Surface"))
      end

      def plan_retirements(request, targets, intent, index:)
        retiring = targets.select { |_occurrence, record| retiring?(record, intent) }
        return {} if retiring.empty?

        Zones.retire_pairs(request, retiring, index)
      end

      def classify_updates(request, targets, retirements, intent)
        targets.filter_map do |occurrence, record|
          key = Zones::Occurrences.key(occurrence.reference)
          # A Face the gesture also retires is patched from its retired record, so it is written once.
          base = retirements.key?(key) ? retirements.fetch(key).after : record
          after = patched_record(request, occurrence, base, intent)
          next unless after

          stamp = Zones::Schema.stamp(occurrence.zone.record)
          next if record == after && Zones::STAMP_STORE.read(occurrence.entity) == stamp

          { "reference" => occurrence.reference(record&.fetch("id", nil)), "before" => record, "after" => after,
            "stamp" => stamp, "change" => record ? "updated" : "created" }
        end
      end

      # A counterpart dragged in by retirement that the gesture does not itself classify. It loses its
      # boundary condition and keeps everything else.
      def retirement_only_updates(targets, retirements)
        classified = targets.map { |occurrence, _record| Zones::Occurrences.key(occurrence.reference) }
        retirements.reject { |key, _update| classified.include?(key) }.map do |_key, update|
          { "reference" => update.reference, "before" => update.before, "after" => update.after, "stamp" => nil,
            "change" => "retired" }
        end
      end

      def new_record(request, occurrence)
        {
          "id" => Records::Identity.derived("fac", "model" => request.model.guid, "revision" => request.revision,
                                                   "zone_path" => occurrence.zone.path,
                                                   "entity_path" => occurrence.path),
          "schema_version" => 1, "user_data" => {}, "extension_data" => {}
        }
      end

      def patched_record(request, occurrence, before, intent)
        return nil if before.nil? && intent.values.none? { |operation| operation.fetch("mode") == "set" }

        record = before ? DeepCopy.call(before) : new_record(request, occurrence)
        intent.each do |field, operation|
          case operation.fetch("mode")
          when "keep" then next
          when "clear" then record.delete(field)
          when "set" then record[field] = operation.fetch("value")
          end
        end
        AssemblyAssignment.fill_hints(request, record, intent)
        # The reference belongs to the condition. Moving off AttachedZone drops it, so no Face keeps a
        # reference its own condition no longer explains; but a caller asking for the reference
        # without the condition is refused rather than having the value quietly discarded.
        unless record["boundary_condition"] == "AttachedZone"
          if intent.dig("attached_zone_id", "mode") == "set"
            raise CodedError.new("params.invalid",
                                 "Setting attached_zone_id needs the AttachedZone boundary condition.")
          end

          record.delete("attached_zone_id")
        end
        Schema.validate!(record)
      end

      def validate_intent!(intent)
        raise CodedError.new("params.invalid", "Classify needs at least one field intent.") if intent.empty?

        intent.each do |field, operation|
          mode = operation.fetch("mode")
          value = operation["value"]
          if mode == "set" && value.nil?
            raise CodedError.new("params.invalid", "Set intent for #{field} needs a value.")
          end
          if field == "face_type" && mode == "set" && !ASSIGNABLE_FACE_TYPES.include?(value)
            raise CodedError.new("params.invalid", "Classify sets Wall, RoofCeiling or Floor.")
          end

          if field == "boundary_condition" && mode == "set" && !ASSIGNABLE_BOUNDARIES.include?(value)
            raise CodedError.new("params.invalid",
                                 "Classify sets #{ASSIGNABLE_BOUNDARIES.join(', ')}; Surface is the solver's.")
          end
        end
      end

      def check_expected!(before, expected)
        values = before ? Schema.values(before) : {}
        changed = expected.keys.reject { |key| values[key] == expected[key] }
        return if changed.empty?

        raise CodedError.new("target.changed", "The Face changed since it was read (#{changed.join(', ')}).")
      end
      private_class_method :projected_view
      private_class_method :face_view, :patched_record, :validate_intent!, :deduplicate,
                           :retiring?, :plan_retirements, :classify_updates,
                           :retirement_only_updates, :plan_classification
    end
  end
end
