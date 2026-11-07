# frozen_string_literal: true

module PhComposer
  module Spaces
    # The Spaces handlers: they read and propose; the dispatcher owns the native operation. Every
    # target is an explicit reference; a Zone and its loose Faces are reached through the Zones
    # targets' public locate, never through Zones internals.
    module Authoring
      ZONE_KIND = "ph_composer.zones.zone"
      FACE_KIND = "ph_composer.zones.faces.face"
      STAMP = "ph_composer.zones.stamp_container"
      # What an edit may change, per kind; identity, structure and metadata have their own actions.
      EDITABLE = {
        SPACE_KIND => %w[name number default_height_m] + AIRFLOWS,
        VOLUME_KIND => %w[display_name avg_ceiling_height_m],
        FLOOR_SEGMENT_KIND => %w[display_name weighting_factor net_area_factor]
      }.freeze
      # Why Create Space leaves a selected Face out, by the refusal Zones' locate gave it.
      LEFT_OUT = {
        "target.not_found" => ["not_found", "That Face no longer exists."],
        "target.wrong_kind" => ["not_a_face", "Only Faces become Floor Segments."],
        "target.wrong_hierarchy" => ["in_container", "The Face is inside another container, not loose in the Zone."],
        "target.shared_definition" => ["shared_storage", "The Face is in storage another copy shares."],
        "target.locked" => ["locked", "The Face or a Group above it is locked."],
        "target.changed" => ["classified", "The Face is an envelope Face with a classification."],
        "target.ambiguous" => ["classified", "The Face is an envelope Face with a classification."]
      }.freeze

      # A Face Create Space would take: the reference the caller named and the Face's persistent id.
      EligibleFace = Struct.new(:reference, :face_id, keyword_init: true)

      # One checked edit of a Space, Volume or Floor Segment record: the occurrence it targets, the record
      # as read and the validated record proposed. `update`, `batch_update` and Height from solid share it.
      RecordEdit = Struct.new(:kind, :occurrence, :before, :after, keyword_init: true) do
        def changed?
          before != after
        end
      end

      # A floor outline drawn on the Zone's walls splits them and shares their Edges, so Create Space leaves
      # it out; the way out is to draw it where it touches no other Face.
      SHARES_EDGE = "The Face shares an Edge with an unselected Face; grouping it would split that Face. Undo " \
                    "the outline, then draw it just below the floor or inset from the walls, touching no other Face."
      # A solid's walls are left out as walls; its top and bottom then share Edges with them. Taking both
      # would count the floor twice, so neither is taken.
      SOLID = "The Face is part of a solid. A Space is a floor outline plus a height: draw the floor outline " \
              "alone, touching no other Face, then set the height, or group the solid and use Height from solid."

      module_function

      # Which Faces Create Space would take and which it leaves out, and why. Writes nothing.
      def create_preview(request, zone:, faces:)
        request.locate(ZONE_KIND, zone_reference(zone), :mutable => true)
        eligible, left_out = partition_faces(request, zone_reference(zone), faces)
        { "accepted" => eligible.map(&:reference), "left_out" => left_out }
      end

      def create(request, proposal, zone:, faces:, name: nil, number: nil, weighting_factor: 1.0)
        zone = zone_reference(zone)
        request.locate(ZONE_KIND, zone, :mutable => true)
        context_open!(request.model, zone.fetch("zone_path"), "Open the Zone's edit context to create a Space in it.")
        eligible, = partition_faces(request, zone, faces)
        face_ids = eligible.map(&:face_id)
        if face_ids.empty?
          raise CodedError.new("space.nothing_to_create",
                               "None of those Faces can become a Space. Nothing was written.")
        end

        scan = Occurrences.scan(request.model)
        allocate = Records::Identity.allocator(request, request.params)
        height = Settings.default_height_m(request.model)
        space = { "id" => allocate.call("spc"), "schema_version" => 1, "name" => name.to_s,
                  "number" => number || next_number(scan, zone.fetch("zone_path")), "default_height_m" => height,
                  "next_volume_sequence" => 2 }
        volume = new_volume(allocate, 1, height)
        segments = segments_for(allocate, face_ids, weighting_factor)
        [[SPACE, space], [VOLUME, volume]].each { |kind, record| Spaces.validate!(kind, record) }
        proposal.add_step(GroupStep.new(:context_path => zone.fetch("zone_path"), :face_ids => face_ids,
                                        :space => space, :volume => volume, :segments => segments,
                                        :slot => space.fetch("id")),
                          :scopes => [Operations::EntityScope.new(zone.fetch("zone_path"))])
        request.participate(STAMP, "zone" => zone, "slot" => space.fetch("id"))
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

      # The explicit repair of a copy: the named occurrence and everything inside it take new ids, in one
      # step. A Space takes the next free number in its Zone.
      def make_independent(request, proposal, reference:)
        scan = Occurrences.scan(request.model)
        kind = Resolve.kind_of(reference)
        target = Resolve.occurrence(scan, reference, :mutable => false)
        zone = zone_of(request, target.path)
        if kind == SPACE_KIND
          number = next_number(scan, zone, zone_paths(request), reserved_numbers(proposal, zone))
        end
        plan = IdentityPlan.build(scan, target, :number => number,
                                                :allocate => Records::Identity.allocator(request, request.params),
                                                :catalog => request.registry.catalog, :engine => request.engine)
        scope = kind == FLOOR_SEGMENT_KIND ? target.path[0...-2] : target.path[0...-1]
        proposal.add_step(IdentityStep.new(:plan => plan, :target => target, :zone_path => zone),
                          :scopes => [Operations::EntityScope.new(scope)])
        renamed = plan.rows.reject { |row| row.after["id"] == row.before["id"] }
        ids = renamed.map { |row| { "kind" => row.kind, "before" => row.before["id"], "after" => row.after["id"] } }
        { "ids" => ids }
      end

      # Moves a Space Group, with everything in it, into another Zone where it stands; the new Group takes
      # the target Zone's stamp. Loose geometry beside the Space stays where it is.
      def move_to_zone(request, proposal, space:, zone:)
        scan = Occurrences.scan(request.model)
        source = Resolve.occurrence(scan, space, :mutable => true)
        zone = zone_reference(zone)
        located = request.locate(ZONE_KIND, zone, :mutable => true)
        MovePlan.refuse!(:space => source, :current_zone_path => zone_of(request, source.path),
                         :target_zone_path => zone.fetch("zone_path"),
                         :open_path => EditContext.current_ids(request.model))
        transform = MovePlan.transform(source.transform, located.transform * located.entity.transformation)
        slot = "#{source.record.fetch('id')}.moved"
        proposal.add_step(MoveStep.new(:source => source, :target_zone_path => zone.fetch("zone_path"),
                                       :transform => transform, :slot => slot),
                          :scopes => [Operations::EntityScope.new(source.path[0...-1]),
                                      Operations::EntityScope.new(zone.fetch("zone_path"))])
        request.participate(STAMP, "zone" => zone, "slot" => slot)
        { "space_id" => source.record.fetch("id"), "zone_id" => zone.fetch("zone_id") }
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

      # Splits the selected Faces into the EligibleFaces Create Space would take and a left-out row,
      # with its reason, for each of the rest.
      def partition_faces(request, zone, faces)
        index = request.locate_index(FACE_KIND)
        candidates = []
        left_out = []
        faces.uniq.each do |reference|
          reason = face_refusal(request, zone, reference, index)
          if reason
            left_out << { "reference" => reference, "reason" => reason.first, "message" => reason.last }
          else
            candidates << EligibleFace.new(:reference => reference,
                                           :face_id => Integer(reference.fetch("entity_path").last))
          end
        end
        located_zone = request.locate(ZONE_KIND, zone, :mutable => false)
        eligible = without_edge_sharing(located_zone, candidates)
        walls = left_out.select { |row| row["reason"] == "vertical" }
                        .map { |row| Integer(row.dig("reference", "entity_path").last) }
        left_out.concat((candidates - eligible).map do |face|
          solid = part_of_solid?(located_zone.entity.entities, face.face_id, walls)
          reason = solid ? ["solid", SOLID] : ["shares_edge", SHARES_EDGE]
          { "reference" => face.reference, "reason" => reason.first, "message" => reason.last }
        end)
        [eligible, left_out]
      end

      # Whether every Edge of the Face bounds one of the selected walls: the top or bottom of a drawn solid,
      # not an outline that merely touches a wall.
      def part_of_solid?(entities, face_id, walls)
        face = entities.to_a.find { |entity| entity.persistent_id == face_id }
        edges = Array(face&.edges)
        !edges.empty? && edges.all? { |edge| Array(edge.faces).any? { |other| walls.include?(other.persistent_id) } }
      end

      # The candidates that share no Edge with a Face outside the set. Dropping a Face makes it an
      # outside neighbour of the Faces beside it, so the check repeats until nothing more drops.
      def without_edge_sharing(located_zone, candidates)
        kept = candidates
        loop do
          sharing_ids = Steps.sharing(located_zone.entity.entities, kept.map(&:face_id))
          return kept if sharing_ids.empty?

          kept = kept.reject { |face| sharing_ids.include?(face.face_id) }
        end
      end

      def face_refusal(request, zone, reference, index)
        return ["other_zone", "The Face is in another Zone."] unless reference.slice("zone_id", "zone_path") == zone
        return LEFT_OUT.fetch("target.changed") if reference["entity_id"]
        unless reference.fetch("entity_path").length == 1
          return ["not_in_zone_context", "The Face is not loose in the Zone's own edit context."]
        end

        located = request.locate(FACE_KIND, reference, :mutable => true, :index => index)
        return ["floor_segment", "The Face is already a Floor Segment."] if FLOOR_SEGMENT_STORE.read(located.entity)
        return ["vertical", Eligibility::WALL] if Eligibility.wall?(located.entity, located.transform)

        nil
      rescue CodedError => error
        LEFT_OUT.fetch(error.code) { raise }
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

      # The next free whole number among the Spaces already in this Zone, or outside every Zone when
      # `zone_path` is nil, and the `reserved` numbers; `zone_paths` are every Zone's, so a Space in a
      # nested Zone counts only there.
      def next_number(scan, zone_path, zone_paths = [zone_path], reserved = [])
        numbers = scan.spaces.select { |space| Occurrences.zone_path(space.path, zone_paths.compact) == zone_path }
                      .map { |space| space.record.fetch("number") }
        numbers = (numbers + reserved).filter_map { |number| Integer(number, 10, :exception => false) }
        ((numbers.max || 0) + 1).to_s
      end

      # The Space numbers earlier repairs in this proposal give in the Zone at `zone_path`. A host
      # follow-up plans every copy against one Model state, so a later repair must not reuse them.
      def reserved_numbers(proposal, zone_path)
        proposal.steps.grep(IdentityStep).select { |step| step.zone_path == zone_path }.filter_map(&:number)
      end

      def zone_paths(request)
        request.query(Reads::ZONES_READ).fetch("zones").map { |zone| zone.dig("reference", "zone_path") }
      end

      def zone_of(request, path)
        Occurrences.zone_path(path, zone_paths(request))
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
