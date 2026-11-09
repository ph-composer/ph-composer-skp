# frozen_string_literal: true

module PhComposer
  module Spaces
    # The Spaces handlers: they read and propose; the dispatcher owns the native operation. Every
    # target is an explicit reference; a Zone and its loose Faces are reached through the Zones
    # targets' public locate, never through Zones internals.
    module Authoring
      # What an edit may change, per kind; identity, structure and metadata have their own actions.
      EDITABLE = {
        SPACE_KIND => %w[name number default_height_m] + AIRFLOWS,
        VOLUME_KIND => %w[display_name avg_ceiling_height_m],
        FLOOR_SEGMENT_KIND => %w[display_name weighting_factor net_area_factor]
      }.freeze
      # One checked edit of a Space, Volume or Floor Segment record: the occurrence it targets, the record
      # as read and the validated record proposed. `update`, `batch_update` and Height from solid share it.
      RecordEdit = Struct.new(:kind, :occurrence, :before, :after, keyword_init: true) do
        def changed?
          before != after
        end
      end

      module_function

      # Which Faces Create Space would take from the open edit context, which it leaves out and why, the Zone
      # the review preselects and the height the Space will take. Writes nothing.
      def create_preview(request, faces:)
        found = CreateFaces.read(request, faces)
        { "accepted" => found.eligible.map(&:path), "left_out" => found.left_out,
          "zone" => CreateFaces.preselected_zone(request, found),
          "height_m" => Settings.default_height_m(request.model),
          "height_source" => Settings.read(request.model).fetch("last_height_m") ? "last_height" : "default" }
      end

      # Makes one Space from Faces loose in the open edit context, hosted in `zone`, or in no Zone when it is nil.
      # The Space Group stands where the Faces were drawn, except that it never stays inside a Zone.
      def create(request, proposal, faces:, zone: nil, name: nil, number: nil, weighting_factor: 1.0)
        context = Resolve.integer_path(faces.first)[0...-1]
        context_open!(request.model, context,
                      "A Space is a floor surface plus a height: open the edit context holding its Faces to " \
                      "create a Space from them.")
        found = CreateFaces.read(request, faces)
        face_ids = found.eligible.map(&:face_id)
        if face_ids.empty?
          raise CodedError.new("space.nothing_to_create",
                               "None of those Faces can become a Space. A Space is a floor surface plus a height: " \
                               "select only the floor surface's Faces. Nothing was written.")
        end

        zone_id = zone && host_zone_id(request, zone)
        scan = Occurrences.scan(request.model)
        allocate = Records::Identity.allocator(request, request.params)
        height = Settings.default_height_m(request.model)
        space = { "id" => allocate.call("spc"), "schema_version" => 1, "name" => name.to_s,
                  "number" => number || next_number(scan, zone_id), "default_height_m" => height,
                  "next_volume_sequence" => 2 }
        space["zone_id"] = zone_id if zone_id
        volume = new_volume(allocate, 1, height)
        segments = segments_for(allocate, face_ids, weighting_factor)
        [[SPACE, space], [VOLUME, volume]].each { |kind, record| Spaces.validate!(kind, record) }
        proposal.add_step(GroupStep.new(:context_path => context, :face_ids => face_ids, :space => space,
                                        :volume => volume, :segments => segments, :place_in => found.outside),
                          :scopes => [context, found.outside].compact.map { |path| Operations::EntityScope.new(path) })
        { "space_id" => space.fetch("id"), "volume_id" => volume.fetch("id"),
          "floor_segment_ids" => segments.values.map { |record| record.fetch("id") } }
      end

      # Loose Faces at a Space's root become its next Volume, with the Space's default height.
      def create_volume(request, proposal, space:, faces:, weighting_factor: 1.0)
        scan = Occurrences.scan(request.model)
        occurrence = Resolve.occurrence(scan, space, :mutable => false)
        Eligibility.new_volume!(scan, occurrence)
        context_open!(request.model, occurrence.path, "Open the Space's edit context to add a Volume to it.")
        face_ids = space_root_faces(request.model, occurrence, faces)
        before = occurrence.record
        allocate = Records::Identity.allocator(request, request.params)
        volume = new_volume(allocate, before.fetch("next_volume_sequence"), before.fetch("default_height_m"))
        segments = segments_for(allocate, face_ids, weighting_factor)
        proposal.add_step(GroupStep.new(:context_path => occurrence.path, :face_ids => face_ids, :volume => volume,
                                        :segments => segments),
                          :scopes => [Operations::EntityScope.new(occurrence.path)])
        after = before.merge("next_volume_sequence" => before.fetch("next_volume_sequence") + 1)
        record_step(proposal, SPACE_KIND, occurrence.path, before, after)
        { "volume_id" => volume.fetch("id"), "floor_segment_ids" => segments.values.map { |record| record["id"] } }
      end

      # One record's editable values, guarded by what the caller last read. A null removes an
      # optional value, which for an airflow means unset again.
      def update(request, proposal, reference:, values:, expected_values:)
        edits = [plan_edit(Occurrences.scan(request.model), reference, values, expected_values)]
        propose_edits(request, proposal, edits)
      end

      # Many Spaces, Volumes and Floor Segments in one all-or-nothing step: every target is checked
      # before anything is proposed.
      def batch_update(request, proposal, edits:)
        scan = Occurrences.scan(request.model)
        keys = edits.map { |edit| CanonicalJson.generate(edit.fetch("reference")) }
        raise CodedError.new("params.invalid", "A batch names one target twice.") unless keys.uniq.length == keys.length

        planned = edits.map do |edit|
          plan_edit(scan, edit.fetch("reference"), edit.fetch("values"), edit.fetch("expected_values"))
        end
        propose_edits(request, proposal, planned)
      end

      def remove_volume(request, proposal, volume:)
        occurrence = Resolve.occurrence(Occurrences.scan(request.model), volume, :mutable => true)
        check_removals!(request, proposal, [[VOLUME_KIND, occurrence]] +
                                           occurrence.segments.map { |segment| [FLOOR_SEGMENT_KIND, segment] })
        proposal.add_step(RemoveVolumeStep.new(:path => occurrence.path, :before => occurrence.record,
                                               :segments => occurrence.segments.map { |segment| segment.record["id"] }),
                          :scopes => [Operations::EntityScope.new(occurrence.path[0...-1])])
        { "volume_id" => occurrence.record.fetch("id") }
      end

      # Puts a moved Volume back where its record says it was left, and protects it, in one Undo step.
      def restore_position(request, proposal, volume:)
        model = request.model
        occurrence = Resolve.occurrence(Occurrences.scan(model), volume, :mutable => true)
        if Protection.placement(model, occurrence.entity, occurrence.path[0...-1]) == :unreadable
          raise CodedError.new("space.volume_open", "Close the Volume, or the Volume open beside it, before " \
                                                    "restoring its position. Nothing was written.")
        end
        unless occurrence.record["home_transform"]
          raise CodedError.new("space.position_unknown", "The Volume has no stored position. Nothing was written.")
        end

        moved = Navigation.moved?(model, occurrence)
        if moved
          proposal.add_step(RestorePositionStep.new(:path => occurrence.path, :before => occurrence.record),
                            :scopes => [Operations::EntityScope.new(occurrence.path[0...-1])])
        end
        { "volume_id" => occurrence.record.fetch("id"), "moved" => moved }
      end

      def delete(request, proposal, space:)
        scan = Occurrences.scan(request.model)
        occurrence = Resolve.occurrence(scan, space, :mutable => true)
        check_removals!(request, proposal, inside(scan, occurrence.path))
        proposal.add_step(DeleteSpaceStep.new(:path => occurrence.path, :before => occurrence.record),
                          :scopes => [Operations::EntityScope.new(occurrence.path[0...-1])])
        { "space_id" => occurrence.record.fetch("id") }
      end

      # The Space stops being one and its Faces stay: every record at or below it goes, whatever the hierarchy
      # holds it as, and no record may be one a copy or shared storage would also lose.
      def remove(request, proposal, space:)
        scan = Occurrences.scan(request.model)
        occurrence = Resolve.occurrence(scan, space, :mutable => true)
        removed = inside(scan, occurrence.path)
        removed.each do |kind, found|
          target = Resolve::TARGETS.fetch(kind)
          Resolve.writable!(found, target.occurrences_in(scan), target.label)
        end
        check_removals!(request, proposal, removed)
        records = removed.map { |kind, found| { "kind" => kind, "path" => found.path, "before" => found.record } }
        proposal.add_step(RemoveSpaceStep.new(:path => occurrence.path, :records => records),
                          :scopes => [Operations::EntityScope.new(occurrence.path[0...-1])])
        { "space_id" => occurrence.record.fetch("id") }
      end

      # The explicit repair of a copy: the named occurrence and everything inside it take new ids, in one
      # step. A Space takes the next free number in its Zone.
      def make_independent(request, proposal, reference:)
        scan = Occurrences.scan(request.model)
        kind = Resolve.kind_of(reference)
        target = Resolve.occurrence(scan, reference, :mutable => false)
        zone = target.record["zone_id"]
        number = next_number(scan, zone, reserved_numbers(proposal, zone)) if kind == SPACE_KIND
        plan = IdentityPlan.build(scan, target, :number => number,
                                                :allocate => Records::Identity.allocator(request, request.params),
                                                :catalog => request.registry.catalog, :engine => request.engine)
        scope = kind == FLOOR_SEGMENT_KIND ? target.path[0...-2] : target.path[0...-1]
        proposal.add_step(IdentityStep.new(:plan => plan, :target => target, :zone_id => zone),
                          :scopes => [Operations::EntityScope.new(scope)])
        renamed = plan.rows.reject { |row| row.after["id"] == row.before["id"] }
        ids = renamed.map { |row| { "kind" => row.kind, "before" => row.before["id"], "after" => row.after["id"] } }
        { "ids" => ids }
      end

      # Hosts a Space in another Zone: its record names the Zone, and its Group stays where it stands.
      def move_to_zone(request, proposal, space:, zone:)
        source = Resolve.occurrence(Occurrences.scan(request.model), space, :mutable => true)
        zone = zone_reference(zone)
        request.locate(ZONE_KIND, zone, :mutable => false)
        if source.record["zone_id"] == zone.fetch("zone_id")
          raise CodedError.new("space.same_zone", "The Space is already in that Zone. Nothing was written.")
        end

        record_step(proposal, SPACE_KIND, source.path, source.record,
                    source.record.merge("zone_id" => zone.fetch("zone_id")))
        { "space_id" => source.record.fetch("id"), "zone_id" => zone.fetch("zone_id") }
      end

      # Takes a Space out of its Zone, the repair for one whose Zone is gone: the record names no Zone
      # and the Group stays where it stands. A Space already in no Zone adds no step.
      def unhost(request, proposal, space:)
        occurrence = Resolve.occurrence(Occurrences.scan(request.model), space, :mutable => true)
        before = occurrence.record
        record_step(proposal, SPACE_KIND, occurrence.path, before, before.reject { |key, _value| key == "zone_id" }) if
          before.key?("zone_id")
        { "space_id" => before.fetch("id") }
      end

      # Marks explicit Faces directly inside Volumes as Floor Segments with one weighting factor; a Face
      # already marked keeps its record and takes the factor.
      def mark_floors(request, proposal, faces:, weighting_factor:)
        limit = Spaces.floor_gesture_limit
        count = faces.uniq.length
        if count > limit
          raise CodedError.new("gesture.too_large",
                               "One Mark floor gesture marks at most #{limit} Faces; this one names #{count}.")
        end

        scan = Occurrences.scan(request.model)
        allocate = Records::Identity.allocator(request, request.params)
        ids = faces.map { |path| Resolve.integer_path(path) }.uniq.map do |path|
          before = marked_floor_segment(request.model, scan, path)
          after = (before || new_segment(allocate)).merge("weighting_factor" => weighting_factor)
          Spaces.validate!(FLOOR_SEGMENT, after)
          record_step(proposal, FLOOR_SEGMENT_KIND, path, before, after) unless before == after
          after.fetch("id")
        end
        { "floor_segment_ids" => ids }
      end

      # The Floor Segment record already on the Face at `path`, or nil when it is not yet marked. Refuses a
      # path that is not a Face directly inside a writable Volume, or a marked Face that cannot be written.
      def marked_floor_segment(model, scan, face_path)
        volume = (scan.volumes + scan.orphan_volumes).find { |candidate| candidate.path == face_path[0...-1] }
        unless volume
          raise CodedError.new("target.wrong_hierarchy", "Mark floor takes Faces directly inside a Volume.")
        end

        Eligibility.floor!(scan, volume)
        face = Occurrences.entity_at(model, face_path)
        raise CodedError.new("target.wrong_kind",
                             "Only Faces become Floor Segments.") unless face.is_a?(Sketchup::Face)

        stored = FLOOR_SEGMENT_STORE.read(face)
        unless stored
          Eligibility.not_a_wall!(face, volume.transform)
          return nil
        end

        reference = { "floor_segment_id" => stored.fetch("id"), "entity_path" => face_path }
        Resolve.occurrence(scan, reference, :mutable => true).record
      end

      # The Floor Segment records go; the Faces stay.
      def unmark_floors(request, proposal, floor_segments:)
        scan = Occurrences.scan(request.model)
        occurrences = floor_segments.uniq.map { |reference| Resolve.occurrence(scan, reference, :mutable => true) }
        check_removals!(request, proposal, occurrences.map { |occurrence| [FLOOR_SEGMENT_KIND, occurrence] })
        occurrences.each do |occurrence|
          record_step(proposal, FLOOR_SEGMENT_KIND, occurrence.path, occurrence.record, nil)
        end
        { "floor_segment_ids" => occurrences.map { |occurrence| occurrence.record.fetch("id") } }
      end

      # Every Spaces record at or below `path`, whatever the hierarchy holds it as: what erasing it removes.
      def inside(scan, path)
        Resolve::TARGETS.flat_map do |kind, target|
          target.occurrences_in(scan).select { |occurrence| occurrence.path[0, path.length] == path }
                .map { |occurrence| [kind, occurrence] }
        end
      end

      # Refuses `reference.in_use` when any record, a readable unavailable extension's included, would
      # still name an identity this proposal removes (context/EXTENSIBILITY.md, "Entity-owned reference
      # targets"). `removed` pairs each kind with the occurrence that goes.
      def check_removals!(request, proposal, removed)
        plan = Records::ReferencePlan.new(:entries => [], :removals => removed.map do |kind, occurrence|
          Records::ReferenceRemoval.new(:kind => kind, :key => occurrence.path, :before => occurrence.record)
        end)
        removed.each do |kind, occurrence|
          request.engine.check_identity_removal!(kind, occurrence.record.fetch("id"),
                                                 :change_set => proposal.record_changes, :reference_plan => plan)
        end
      end

      # Replaces whole `user_data` maps and installed extension payloads on explicit Spaces, Volumes and
      # Floor Segments (Records::Metadata), in one step; a batch that writes what is stored adds none.
      def update_metadata(request, proposal, updates:)
        scan = Occurrences.scan(request.model)
        catalog = request.registry.catalog
        rows = Records::Metadata.distinct_updates(updates).map do |update|
          reference = update.fetch("reference")
          occurrence = Resolve.occurrence(scan, reference, :mutable => true)
          kind = Resolve.kind_of(reference)
          after = Records::Metadata.planned(request.engine, catalog, occurrence.record, update, KINDS[kind].label)
          [reference, kind, occurrence, Spaces.validate!(KINDS.fetch(kind), after)]
        end
        rows.each do |_reference, kind, occurrence, after|
          record_step(proposal, kind, occurrence.path, occurrence.record, after) unless occurrence.record == after
        end
        { "updates" => rows.map do |reference, _kind, _occurrence, after|
          { "reference" => reference, "extension_status" => Records::Metadata.status_map(after, catalog) }
        end }
      end

      def space_root_faces(model, occurrence, faces)
        faces.map do |path|
          path = Resolve.integer_path(path)
          unless path[0...-1] == occurrence.path
            raise CodedError.new("target.wrong_hierarchy", "A new Volume takes Faces loose at its Space's root.")
          end

          face = Occurrences.entity_at(model, path)
          unless face.is_a?(Sketchup::Face) && FLOOR_SEGMENT_STORE.read(face).nil?
            raise CodedError.new("target.wrong_kind", "A new Volume takes loose Faces that are not yet marked.")
          end

          Eligibility.not_a_wall!(face, occurrence.transform)

          face.persistent_id
        end.uniq.tap do |ids|
          entities = Occurrences.entity_at(model, occurrence.path).entities
          unless Steps.closed_shells(entities, ids).empty?
            raise CodedError.new("target.wrong_kind", "The Faces close a solid. #{CreateFaces::SOLID}")
          end
          unless Steps.sharing(entities, ids).empty?
            raise CodedError.new("space.shares_edge", "A Face shares an Edge with a Face that is not part of the " \
                                                      "new Volume; grouping it would split that Face. Nothing was " \
                                                      "written.")
          end
        end
      end

      def plan_edit(scan, reference, values, expected_values)
        occurrence = Resolve.occurrence(scan, reference, :mutable => true)
        kind = Resolve.kind_of(reference)
        unknown = (values.keys | expected_values.keys) - EDITABLE.fetch(kind)
        unless unknown.empty?
          raise CodedError.new("params.invalid",
                               "A #{KINDS.fetch(kind).label} edit cannot change #{unknown.join(', ')}.")
        end

        before = occurrence.record
        (values.keys | expected_values.keys).each do |key|
          next if before[key] == expected_values[key]

          raise CodedError.new("target.changed", "#{KINDS.fetch(kind).label} #{before['id']} changed since it was " \
                                                 "read. Nothing was written.")
        end
        after = before.merge(values).compact
        RecordEdit.new(:kind => kind, :occurrence => occurrence, :before => before,
                       :after => Spaces.validate!(KINDS.fetch(kind), after))
      end

      # Proposes each changed RecordEdit. A height among them becomes the Model's last height; when a
      # batch changes several, the last one in the batch wins.
      def propose_edits(request, proposal, edits)
        last_height_m = nil
        edits.each do |edit|
          next unless edit.changed?

          record_step(proposal, edit.kind, edit.occurrence.path, edit.before, edit.after)
          key = height_key(edit.kind)
          last_height_m = edit.after[key] if key && edit.after[key] && edit.after[key] != edit.before[key]
        end
        record_height(request, proposal, last_height_m) if last_height_m
        { "ids" => edits.map { |edit| edit.occurrence.record.fetch("id") } }
      end

      def height_key(kind)
        { SPACE_KIND => "default_height_m", VOLUME_KIND => "avg_ceiling_height_m" }[kind]
      end

      # A height edit records the value entered as the Model's last height, which new Spaces take.
      def record_height(request, proposal, height)
        current = Settings.read(request.model)
        return if current.fetch("last_height_m") == height

        Settings.propose(request, proposal, :values => current.merge("last_height_m" => height),
                                            :expected_values => current)
      end

      def record_step(proposal, kind, path, before, after)
        name = case kind
               when SPACE_KIND then after && Names.space(after)
               when VOLUME_KIND then after && Names.volume(after)
               end
        proposal.add_step(RecordStep.new(:kind => kind, :path => path, :before => before, :after => after,
                                         :name => name),
                          :scopes => [Operations::EntityScope.new(group_scope(kind, path))])
      end

      # The Group whose contents a record write touches: a Group's own parent, a Face's Volume's parent.
      def group_scope(kind, path)
        kind == FLOOR_SEGMENT_KIND ? path[0...-2] : path[0...-1]
      end

      def new_volume(allocate, number, height)
        { "id" => allocate.call("vol"), "schema_version" => 1, "number" => number, "display_name" => "",
          "avg_ceiling_height_m" => height, "floor_id" => allocate.call(FLOOR_PREFIX) }
      end

      def new_segment(allocate)
        { "id" => allocate.call("fsg"), "schema_version" => 1, "display_name" => "", "weighting_factor" => 1.0,
          "net_area_factor" => 1.0 }
      end

      def segments_for(allocate, face_ids, weighting_factor)
        face_ids.to_h do |id|
          record = new_segment(allocate).merge("weighting_factor" => weighting_factor)
          [id.to_s, Spaces.validate!(FLOOR_SEGMENT, record)]
        end
      end

      # The next free whole number among the Spaces hosted in this Zone, or in no Zone when `zone_id` is
      # nil, and the `reserved` numbers.
      def next_number(scan, zone_id, reserved = [])
        numbers = scan.spaces.select { |space| space.record["zone_id"] == zone_id }
                      .map { |space| space.record.fetch("number") }
        numbers = (numbers + reserved).filter_map { |number| Integer(number, 10, :exception => false) }
        ((numbers.max || 0) + 1).to_s
      end

      # The Space numbers earlier repairs in this proposal give in the Zone `zone_id`. A host follow-up
      # plans every copy against one Model state, so a later repair must not reuse them.
      def reserved_numbers(proposal, zone_id)
        proposal.steps.grep(IdentityStep).select { |step| step.zone_id == zone_id }.filter_map(&:number)
      end

      # The id of a Zone a Space is hosted in. Nothing inside the Zone is written, so it need not be writable.
      def host_zone_id(request, zone)
        reference = zone_reference(zone)
        request.locate(ZONE_KIND, reference, :mutable => false)
        reference.fetch("zone_id")
      end

      def zone_reference(zone)
        { "zone_id" => zone.fetch("zone_id"), "zone_path" => Resolve.integer_path(zone.fetch("zone_path")) }
      end

      def context_open!(model, path, message)
        return if Array(model.active_path).map(&:persistent_id) == path

        raise CodedError.new("space.context_required", "#{message} Nothing was written.")
      end
    end
  end
end
