# frozen_string_literal: true

module PhComposer
  module Zones
    # The Zone handlers the declarations register: reads, Make, Edit and the repairs. Each only reads
    # and proposes; the dispatcher owns the native operation.

    module_function

    def reference_entries(model)
      Occurrences.zones(model).map do |zone|
        Records::ReferenceEntry.new(:kind => REFERENCE_KIND, :key => zone.path, :record => zone.record)
      end
    end

    # Which Zone occurrence holds each root-to-entity path, or why none does, and the refusal a write through
    # the path meets (Occurrences.containment). It walks only along each path, so a pointer move may ask.
    def containment(request, paths:)
      { "paths" => paths.map do |path|
        found = Occurrences.containment(request.model, path)
        { "path" => path, "zone" => found.zone && containment_zone(request.engine, found.zone),
          "entity_path" => found.entity_path, "reason" => found.reason, "write_refusal" => found.write_refusal }
      end }
    end

    # A Zone's reference with its Building-Segment and Level names, read as zones.all shows them.
    def containment_zone(engine, zone)
      record = zone.record
      names = record.fetch("schema_version") == 1 ? record : Options.display(engine, record)
      zone.reference.merge("building_segment" => names["building_segment"], "level" => names["level"])
    end

    def repair_split_face(request, proposal, zone:, face_id:, zones:, retaining_entity_path: nil)
      plan = SplitIdentityRepair.plan(request, :zone => zone, :face_id => face_id, :zones => zones,
                                               :retaining_entity_path => retaining_entity_path)
      scopes = plan.fetch(:scope_paths).map { |path| Operations::EntityScope.new(path) }
      proposal.add_step(SplitIdentityRepair::Step.new(plan), :scopes => scopes)
      plan.fetch(:value)
    end

    def repair_identity(request, proposal, zone_path:)
      zone = Repair.occurrence_at(request.model, zone_path)
      plan = Repair.identity_plan(request.model, zone, request.revision, request.registry.catalog, request.engine)
      proposal.add_step(RepairIdentityStep.new(:reference => zone.reference, :plan => plan),
                        :scopes => [Operations::EntityScope.new(zone.path[0...-1])])
      { "zone_id" => plan.fetch(:record).fetch("id"), "retired_pairs" => retired_pairs(plan) }
    end

    # The explicit route out of a copied Zone: storage of its own, then a new identity, as one step.
    # The original keeps its id, Faces and pairs; the copy's Surface pairs are retired.
    def make_independent(request, proposal, zone_path:)
      zone = Repair.occurrence_at(request.model, zone_path)
      refusal = Repair.independence_refusal(request.model, zone)
      raise refusal if refusal

      catalog = request.registry.catalog
      plan = Repair.identity_plan(request.model, zone, request.revision, catalog, request.engine, :isolating => true)
      proposal.add_step(MakeIndependentStep.new(:reference => zone.reference, :plan => plan, :catalog => catalog),
                        :scopes => [Operations::EntityScope.new(zone.path[0...-1])])
      # Features owning records inside the occurrence add their steps after this one, so they apply
      # once storage is isolated. Zones names none of them (context/CONTRACTS.md, "Compound proposals").
      request.contribute_transition(TRANSITION, "zone_path" => zone.path, "old_zone_id" => zone.record.fetch("id"),
                                                "new_zone_id" => plan.fetch(:record).fetch("id"),
                                                "mapping" => plan.fetch(:mapping), "revision" => request.revision,
                                                "references" => plan.fetch(:reference_plan).entries.map do |entry|
                                                  { "kind" => entry.kind, "key" => entry.key, "record" => entry.record }
                                                end)
      { "zone_id" => plan.fetch(:record).fetch("id"), "retired_pairs" => retired_pairs(plan),
        "storage_isolated" => MakeIndependentStep.shared_storage?(zone.entity) }
    end

    # The stamp-container participant: refuses now what the step would, then stamps at apply the Group
    # the caller's earlier step left in `slot`.
    def stamp_container(request, proposal, zone:, slot:)
      located = Occurrences.locate_zone(request.model, zone, :mutable => true)
      proposal.add_step(StampContainerStep.new(:zone => located.reference, :slot => slot),
                        :scopes => [Operations::EntityScope.new(located.parent_path)])
      { "zone_id" => located.reference.fetch("zone_id") }
    end

    def plan_refusal(request, zone)
      Repair.identity_plan(request.model, zone, request.revision, request.registry.catalog, request.engine,
                           :isolating => true)
      nil
    rescue CodedError => error
      error
    end

    def retired_pairs(plan)
      plan.fetch(:faces).count { |face| face.fetch(:before)&.fetch("boundary_condition", nil) == "Surface" }
    end

    def restore(request, proposal, parent_path:, zone_id:)
      record, offer = Repair.restore_plan(request.model, parent_path, zone_id)
      if record.fetch("schema_version") == 2 && Options::Adoption.needs_adoption?(request.engine, record)
        Options.refuse("zone.options_adoption_required", "Adopt the recoverable choices before Restore")
      end
      parent_path = Occurrences.integer_path(parent_path)
      step = MakeZoneStep.new(:parent_path => parent_path, :entity_ids => offer.fetch("entity_ids"),
                              :record => record, :regroup => true)
      proposal.add_step(step, :scopes => [Operations::EntityScope.new(parent_path)])
      proposal.add_finding(
        "code" => "zone.restore_is_limited", "severity" => "info",
        "message" => "Restore recovers the Zone id, Building-Segment and Level. " \
                     "#{offer.fetch('unrecoverable').join(', ')} went with the Group and are not recovered."
      )
      { "zone_id" => record.fetch("id"), "member_count" => offer.fetch("member_count"),
        "unrecoverable" => offer.fetch("unrecoverable") }
    end

    # One page of Zone occurrences in path order, filtered by id or path; `fields` projects each row to
    # its identity, state and the named values. The Make Zone target and the restorable Zones are
    # small and whole on every page.
    def list(request)
      params = request.params
      zones = Occurrences.zones(request.model)
      duplicates = duplicate_ids(zones)
      counts = zones.map { |zone| zone.record.fetch("id") }.tally
      zones = zones.select { |zone| params["ids"].include?(zone.record.fetch("id")) } if params.key?("ids")
      zones = zones.select { |zone| params["paths"].include?(zone.path) } if params.key?("paths")
      zones = zones.sort_by(&:path)
      page, next_cursor = Pages.slice(request, "#{FEATURE_ID}.list", zones, :key => :path.to_proc)
      rows = page.map do |zone|
        row = zone_view(zone, duplicates.include?(zone.record.fetch("id")), request, counts)
        params.key?("fields") ? project_row(row, params["fields"]) : row
      end
      overview(request.model, rows).merge("next_cursor" => next_cursor, "total" => zones.length)
    end

    # Every Zone occurrence, whole: the panel's projection. Scripts page `list` instead.
    def all(request)
      zones = Occurrences.zones(request.model)
      duplicates = duplicate_ids(zones)
      counts = zones.map { |zone| zone.record.fetch("id") }.tally
      overview(request.model, zones.map { |zone|
                                zone_view(zone, duplicates.include?(zone.record.fetch("id")), request, counts)
                              })
    end

    def overview(model, rows)
      { "zones" => rows, "make_zone" => make_target(model), "restorable" => Repair.orphans(model),
        "findings" => Occurrences.component_findings(model),
        "units" => { "ground_depth_mm" => "mm", "face_area_m2" => "m2", "unclassified_face_area_m2" => "m2" } }
    end

    def duplicate_ids(zones)
      zones.group_by { |zone| zone.record.fetch("id") }.select { |_id, rows| rows.length > 1 }.keys
    end

    def project_row(row, fields)
      row.slice("id", "reference", "state").merge("values" => row.fetch("values").slice(*fields))
    end

    # `name` defaults to the next free "Zone N".
    def make(request, proposal, parent_path:, entity_ids:, name: nil)
      parent_path = Occurrences.integer_path(parent_path)
      entity_ids = entity_ids.map { |id| Integer(id) }
      validate_make_target!(request.model, parent_path, entity_ids)
      zone_id = Records::Identity.derived("zon", "model" => request.model.guid, "revision" => request.revision,
                                                 "parent_path" => parent_path, "entity_ids" => entity_ids.sort)
      if Occurrences.zones(request.model).any? { |zone| zone.record.fetch("id") == zone_id }
        raise CodedError.new("target.ambiguous", "The proposed Zone identity is already present.")
      end

      name ||= default_name(request.model)
      segment = Options.ensure_default(request, proposal)
      record = {
        "id" => zone_id, "schema_version" => 2, "name" => name,
        "building_segment_id" => segment.fetch("id"), "level_id" => nil,
        "ground_depth_mm" => 0.0, "user_data" => {}, "extension_data" => {}
      }
      record["choice_evidence"] = Options.evidence(request.engine, record, proposal)
      Schema.validate!(record)
      step = MakeZoneStep.new(:parent_path => parent_path, :entity_ids => entity_ids, :record => record)
      proposal.add_step(step, :scopes => [Operations::EntityScope.new(parent_path)])
      settings = Faces::Settings.read(request.model)
      if settings.fetch("suggest_on_make")
        suggestion = Faces::SuggestMadeZoneStep.new(:zone_id => zone_id, :request => request, :settings => settings)
        proposal.add_step(suggestion,
                          :scopes => [Operations::EntityScope.new(parent_path)])
      end
      { "zone_id" => zone_id }
    end

    def update(request, proposal, reference:, values:, expected_values:)
      occurrence = Occurrences.resolve_zone(request.model, reference, :mutable => true)
      before = occurrence.record
      if before.fetch("schema_version") == 2 && Options::Adoption.needs_adoption?(request.engine, before)
        Options.refuse("zone.options_adoption_required", "Adopt copied Zone choices before editing")
      end
      expected = Options.adapt_values(request.engine, before, expected_values)
      values = Options.adapt_values(request.engine, before, values)
      changed = expected.keys.reject { |key| before[key] == expected[key] }
      unless changed.empty?
        raise CodedError.new("target.changed", "The Zone changed since it was read (#{changed.join(', ')}).")
      end

      after = DeepCopy.call(before)
      values.each { |key, value| after[key] = DeepCopy.call(value) }
      after["choice_evidence"] = Options.evidence(request.engine, after) if after.fetch("schema_version") == 2
      Schema.validate!(after)
      return { "zone_id" => before.fetch("id") } if before == after

      scope = Operations::EntityScope.new(reference.fetch("zone_path")[0...-1])
      proposal.add_step(UpdateZoneStep.new(:reference => reference, :before => before, :after => after),
                        :scopes => [scope])
      { "zone_id" => after.fetch("id") }
    end

    # The user_data and installed extension payloads of explicit Zone occurrences, guarded by the two
    # maps as last read, in one step per Zone (context/CONTRACTS.md, "Records and extension data").
    def update_metadata(request, proposal, updates:)
      catalog = request.registry.catalog
      rows = Records::Metadata.distinct_updates(updates).map do |update|
        reference = update.fetch("reference")
        before = Occurrences.resolve_zone(request.model, reference, :mutable => true).record
        after = Records::Metadata.planned(request.engine, catalog, before, update, "Zone")
        Schema.validate!(after)
        [reference, before, after]
      end
      rows.each do |reference, before, after|
        next if before == after

        proposal.add_step(UpdateZoneStep.new(:reference => reference, :before => before, :after => after),
                          :scopes => [Operations::EntityScope.new(reference.fetch("zone_path")[0...-1])])
      end
      { "updates" => rows.map do |reference, _before, after|
        { "reference" => reference, "extension_status" => Records::Metadata.status_map(after, catalog) }
      end }
    end

    def zone_view(zone, ambiguous, request, counts)
      state = zone_state(zone, ambiguous)
      faces = Occurrences.faces(zone)
      Schema.view(zone.record).merge(face_totals(faces)).merge(
        "extension_status" => Records::Metadata.status_map(zone.record, request.registry.catalog),
        "display" => Options.display(request.engine, zone.record),
        "reference" => zone.reference,
        "state" => state,
        "face_count" => faces.length,
        "independence" => state == "found" ? nil : independence(request, zone, counts.fetch(zone.record.fetch("id")))
      )
    end

    # The occurrence's Face area, whole and unclassified, in square metres through each Face's own
    # transform: the panel shows and sorts these and never sums Faces itself. Unclassified is the Face
    # rows' rule, a Face with no recorded values; a stored record is validated as the Face read validates it.
    def face_totals(faces)
      areas = faces.map do |face|
        record = Faces::FACE_STORE.read(face.entity)
        Faces::Schema.validate!(record) if record
        [Faces::Geometry.area_m2(face), record.nil? || Faces::Schema.values(record).empty?]
      end
      { "face_area_m2" => areas.sum(0.0) { |area, _| area },
        "unclassified_face_area_m2" => areas.sum(0.0) { |area, unclassified| unclassified ? area : 0.0 } }
    end

    # Whether Make Zone independent can act on this occurrence and, when it cannot, why, in the words
    # the panel shows. Availability runs the same plan the action does, so a copy rule or a duplicated
    # Face id that would refuse is never offered. `retired_pairs` is what acting would cost.
    def independence(request, zone, id_count)
      refusal = Repair.independence_refusal(request.model, zone, :id_count => id_count) || plan_refusal(request, zone)
      surface = Occurrences.faces(zone).count do |face|
        Faces::FACE_STORE.read(face.entity)&.fetch("boundary_condition", nil) == "Surface"
      end
      { "available" => refusal.nil?, "code" => refusal&.code, "reason" => refusal&.message,
        "retired_pairs" => surface }
    end

    # The native menu's read-only availability check. Submission reads the same target through
    # the public Zone query, which carries the revision required by the Make Zone action.
    def make_target(model)
      selected = model.selection.to_a
      parent_path = Occurrences.active_path(model)
      parent = Occurrences.entities_at(model, parent_path)
      return nil if selected.empty? || selected.any? { |entity| !parent.include?(entity) }
      return nil unless make_zone_shape?(selected)

      target = { "parent_path" => parent_path, "entity_ids" => selected.map(&:persistent_id) }
      validate_make_target!(model, target.fetch("parent_path"), target.fetch("entity_ids"))
      target
    rescue CodedError
      nil
    end

    def validate_make_target!(model, parent_path, entity_ids)
      unless Occurrences.active_path(model) == parent_path
        raise CodedError.new("target.edit_path_changed", "The active edit path changed before Make Zone.")
      end

      entities = Occurrences.entities_at(model, parent_path)
      selected = entity_ids.map { |id| Occurrences.unique_entity(entities, id) }
      unless make_zone_shape?(selected)
        raise CodedError.new("target.wrong_kind", "Make Zone accepts one Group or loose Faces and Edges.")
      end
      if Array(model.active_path).any? { |entity| ZONE_STORE.read(entity) }
        raise CodedError.new("target.wrong_hierarchy", "A Zone cannot be made inside another Zone.")
      end

      selected.each do |entity|
        if entity.is_a?(Sketchup::Group)
          prefix = parent_path + [entity.persistent_id]
          contains_zone = Occurrences.zones(model).any? { |zone| zone.path[0, prefix.length] == prefix }
          if contains_zone
            raise CodedError.new("target.wrong_hierarchy", "The selected Group is already or contains a Zone.")
          end
        end
        if entity.respond_to?(:locked?) && entity.locked?
          raise CodedError.new("target.locked", "The selected Group is locked.")
        end
      end
    end

    # Make Zone takes one Group, or loose Faces and Edges.
    def make_zone_shape?(selected)
      (selected.length == 1 && selected.first.is_a?(Sketchup::Group)) ||
        selected.all? { |entity| entity.is_a?(Sketchup::Face) || entity.is_a?(Sketchup::Edge) }
    end

    def default_name(model)
      used = Occurrences.zones(model).map { |zone| zone.record.fetch("name") }
      number = 1
      number += 1 while used.include?("Zone #{number}")
      "Zone #{number}"
    end

    # A copied Zone is ambiguous and shared at once, and shared storage is reported first: it is the
    # condition that blocks every repair, and it names what the user has to do. Reporting only the
    # ambiguity would point at identity repair, which is the one thing not available here.
    def zone_state(zone, ambiguous)
      return "shared_definition" if zone.shared_definition
      return "ambiguous" if ambiguous
      return "wrong_hierarchy" if zone.nested

      "found"
    end
    private_class_method :zone_view, :validate_make_target!, :make_zone_shape?, :zone_state, :overview, :duplicate_ids,
                         :project_row, :independence, :retired_pairs, :plan_refusal
  end
end
