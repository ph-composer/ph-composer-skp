# frozen_string_literal: true

module PhComposer
  module Zones
    # Explicit recovery after SketchUp has copied one Face record onto native split pieces.
    # A path can prove which piece retained the old identity; geometry never can.
    module SplitIdentityRepair
      module_function

      # `zones` is the repair's declared scope, which must name `zone` once; `retaining_entity_path`
      # names the piece that keeps the old identity when geometry cannot prove it.
      def plan(request, zone:, face_id:, zones:, retaining_entity_path: nil)
        model = request.model
        index = Index.new(model)
        zone = Occurrences.resolve_zone(model, zone, :mutable => true, :index => index)
        refuse_locked!(zone)
        scope_paths = mutation_scope(model, zones, zone, index)
        old_id = face_id
        unless Faces::ID_PATTERN.match?(old_id)
          raise CodedError.new("params.invalid", "face_id is not a Face identity.")
        end

        originals = split_entries(model, index, zone, old_id)
        envelope = copied_surface_envelope!(originals)
        keeper, basis = keeper_path(originals, envelope, zone, old_id, retaining_entity_path)
        counterpart = reciprocal(model, index, envelope, old_id, scope_paths)
        changes = changed_pieces(request, index, zone, old_id, originals, keeper, envelope)
        if counterpart
          before = counterpart.fetch(:before)
          changes << { :reference => counterpart.fetch(:reference), :before => before,
                       :after => retired(before) }
        end
        result = result_value(old_id, keeper, basis, changes, originals.length)
        { :zone => zone.reference, :old_id => old_id, :changes => changes,
          :piece_paths => originals.map { |entry| entry.fetch(:path) },
          :scope_paths => scope_paths.map { |path| path[0...-1] }.uniq,
          :scope_zones => zones, :choice_path => retaining_entity_path, :value => result }
      end

      def mutation_scope(model, zones, zone, index)
        scope = zones.map do |reference|
          Occurrences.resolve_zone(model, reference, :mutable => true, :index => index)
        end
        paths = scope.map(&:path)
        if paths.uniq.length != paths.length || !paths.include?(zone.path)
          raise CodedError.new("scope.incomplete", "The repair scope must name its Zone exactly once.")
        end

        paths
      end

      def split_entries(model, index, zone, old_id)
        pieces = index.faces_with_id(old_id)
        if pieces.length < 2
          raise CodedError.new("face.identity_unique", "Face #{old_id} does not have split copies to repair.")
        end

        counts = live_identity_counts(model.entities, old_id)
        unless counts.fetch(:ids) == pieces.length && pieces.all? { |piece| piece.zone.path == zone.path }
          raise CodedError.new("target.ambiguous", "The copied Face identity also occurs outside this Zone.")
        end

        parents = pieces.map { |piece| piece.path[0...-1] }.uniq
        if parents.length != 1
          raise CodedError.new("target.ambiguous", "The copied Faces are not in one parent context.")
        end

        pieces.sort_by(&:path).map do |piece|
          actual = Occurrences.face_at(zone, piece.path, :mutable => true)
          before = Faces::FACE_STORE.read(actual.entity)
          raise CodedError.new("target.changed", "A split piece has no Face record.") unless before

          Faces::Schema.validate!(before)
          stamp = STAMP_STORE.read(actual.entity)
          check_stamp!(stamp, zone)
          { :path => piece.path, :before => before, :stamp => stamp }
        end
      end

      def changed_pieces(request, index, zone, old_id, originals, keeper, envelope)
        model = request.model
        occupied = index.faces_by_id.keys
        changes = originals.map do |entry|
          path = entry.fetch(:path)
          before = entry.fetch(:before)
          id = path == keeper ? old_id : Records::Identity.derived("fac", {
            "model" => model.guid, "revision" => request.revision, "old_id" => old_id,
            "zone_path" => zone.path, "entity_path" => path, "repair" => "native_split"
          })
          if id != old_id && (occupied.include?(id) || live_identity_counts(model.entities, id).fetch(:ids) > 0)
            raise CodedError.new("target.ambiguous", "The proposed Face identity already exists.")
          end

          after = DeepCopy.call(before).merge("id" => id)
          after = retired(after) if envelope
          Faces::Schema.validate!(after)
          { :reference => piece_reference(zone, path, old_id), :before => before,
            :after => after, :stamp => entry.fetch(:stamp) }
        end
        if changes.map { |entry| entry.fetch(:after).fetch("id") }.uniq.length != changes.length
          raise CodedError.new("target.ambiguous", "The proposed Face identities are not unique.")
        end

        reference_plan = Records::ReferencePlan.new(:entries => changes.map do |entry|
          Records::ReferenceEntry.new(:kind => Faces::REFERENCE_KIND,
                                      :key => zone.path + entry.fetch(:reference).fetch("entity_path"),
                                      :record => entry.fetch(:after))
        end)
        changes.each do |entry|
          after = entry.fetch(:after)
          id = after.fetch("id")
          after["extension_data"] = Records::Extension.copy_data(
            entry.fetch(:before).fetch("extension_data", {}), request.registry.catalog, "Face", old_id,
            id == old_id ? {} : { old_id => id }, :engine => request.engine, :reference_plan => reference_plan
          )
        end
        changes
      end

      def result_value(old_id, keeper, basis, changes, piece_count)
        {
          "face_id" => old_id, "retaining_entity_path" => keeper, "retention_basis" => basis,
          "pieces" => changes.first(piece_count).map do |entry|
            { "before" => entry.fetch(:reference),
              "after" => entry.fetch(:reference).merge("entity_id" => entry.fetch(:after).fetch("id")) }
          end,
          "retired" => changes.select { |entry| entry.fetch(:before)["boundary_condition"] == "Surface" }
                              .map { |entry| entry.fetch(:reference) }
        }
      end

      def piece_reference(zone, path, id)
        { "zone_id" => zone.record.fetch("id"), "zone_path" => zone.path.dup,
          "entity_path" => path.dup, "entity_id" => id }
      end

      def retired(record)
        after = Faces::Schema.leave_pair!(DeepCopy.call(record))
        after.delete("boundary_condition")
        Faces::Schema.validate!(after)
      end

      def refuse_locked!(zone)
        return unless zone.entity.respond_to?(:locked?) && zone.entity.locked?

        raise CodedError.new("target.locked", "The Zone is locked.")
      end

      def check_stamp!(stamp, zone)
        return if stamp.nil? || stamp["zone_id"] == zone.record.fetch("id")

        raise CodedError.new("target.wrong_zone", "The split Face stamp names another Zone.")
      end

      # Count every stored occurrence, including orphan Faces and repeated component placements.
      # The Zone index alone cannot establish that the duplicate set is complete.
      def live_identity_counts(entities, id, original_pid = nil, counts = nil)
        counts ||= { :ids => 0, :original_pid => 0 }
        entities.each do |entity|
          if entity.is_a?(Sketchup::Face)
            counts[:ids] += 1 if Faces::FACE_STORE.read(entity)&.fetch("id", nil) == id
            counts[:original_pid] += 1 if original_pid && entity.persistent_id == original_pid
          elsif entity.is_a?(Sketchup::Group)
            live_identity_counts(entity.entities, id, original_pid, counts)
          elsif entity.is_a?(Sketchup::ComponentInstance)
            live_identity_counts(entity.definition.entities, id, original_pid, counts)
          end
        end
        counts
      end

      def copied_surface_envelope!(originals)
        surfaces = originals.select { |entry| entry.fetch(:before)["boundary_condition"] == "Surface" }
        return nil if surfaces.empty?
        unless surfaces.length == originals.length &&
               surfaces.map { |entry| entry.fetch(:before).fetch("adjacency") }.uniq.length == 1
          raise CodedError.new("adjacency.unresolved", "The split pieces carry inconsistent Surface links.")
        end

        surfaces.first.fetch(:before).fetch("adjacency")
      end

      # Which split piece keeps the original id, and on what basis. The stored Surface endpoint proves
      # it when it names exactly one piece; otherwise the user must choose, and a choice that
      # contradicts the proof refuses. Ambiguity is never resolved by guessing.
      def keeper_path(originals, envelope, zone, old_id, choice)
        paths = originals.map { |entry| entry.fetch(:path) }
        proved = envelope && proved_keeper(paths, envelope.fetch("self"), zone, old_id)
        selected = choice && Occurrences.integer_path(choice)
        if proved
          if selected && selected != proved
            raise CodedError.new("identity.choice_conflicts", "The stored original endpoint proves another piece.")
          end

          return [proved, "stored_endpoint"]
        end
        unless selected && paths.include?(selected)
          raise CodedError.new("identity.choice_required", "Choose the split piece that retains #{old_id}.",
                               "candidates" => paths)
        end

        [selected, "user_choice"]
      end

      # The one piece path the copied self endpoint names, or nil when it names none or several. An
      # endpoint that does not describe this Face in this Zone refuses: it cannot prove anything.
      def proved_keeper(paths, stored, zone, old_id)
        unless stored["zone_id"] == zone.record.fetch("id") && stored["entity_id"] == old_id &&
               stored["entity_path"].is_a?(Array) && !stored["entity_path"].empty?
          raise CodedError.new("adjacency.unresolved", "The copied Surface self endpoint is inconsistent.")
        end
        return nil unless stored["zone_path"] == zone.path

        matches = paths.select { |path| path == stored["entity_path"] }
        matches.length == 1 ? matches.first : nil
      end

      def reciprocal(model, index, envelope, old_id, scope_paths)
        return nil unless envelope

        stored = envelope.fetch("counterpart")
        other_id = stored.fetch("entity_id")
        if other_id == old_id || stored.fetch("zone_id") == envelope.fetch("self").fetch("zone_id")
          raise CodedError.new("adjacency.unresolved", "The Surface counterpart must be in another Zone.")
        end

        global = live_identity_counts(model.entities, other_id, stored.fetch("entity_path").last)
        if global.fetch(:ids).zero?
          return nil if global.fetch(:original_pid).zero?

          raise CodedError.new("adjacency.unresolved", "The counterpart survives without its Face identity.")
        end
        unless global.fetch(:ids) == 1 && index.faces_with_id(other_id).length == 1
          raise CodedError.new("target.ambiguous", "The Surface counterpart identity is ambiguous.")
        end

        candidate = index.faces_with_id(other_id).first
        stored_zones = index.zones.select { |zone| zone.record.fetch("id") == stored.fetch("zone_id") }
        unless stored_zones.length == 1 && candidate.zone.path == stored_zones.first.path
          raise CodedError.new("adjacency.unresolved", "The Surface counterpart left its authored Zone.")
        end

        actual = candidate.reference(other_id)
        occurrence = Occurrences.resolve_face(model, actual, :mutable => true, :index => index)
        unless scope_paths.include?(occurrence.zone.path)
          raise CodedError.new("scope.incomplete", "The Surface counterpart's Zone is outside the repair scope.",
                               "zones" => [occurrence.zone.reference])
        end
        before = Faces::FACE_STORE.read(occurrence.entity)
        Faces::Schema.validate!(before)
        copied = { "id" => old_id, "boundary_condition" => "Surface", "adjacency" => envelope }
        unless Adjacency.reciprocal?(copied, before)
          raise CodedError.new("adjacency.unresolved", "The Surface counterpart is not reciprocal.")
        end

        # The stored counterpart may have moved. Its unique identity and complete reciprocal
        # envelope prove which actual path to retire; no geometry is involved.
        { :reference => actual, :before => before }
      end

      class Step
        attr_reader :affected

        def initialize(plan)
          @zone = DeepCopy.call(plan.fetch(:zone)).freeze
          @old_id = plan.fetch(:old_id)
          @scope_zones = DeepCopy.call(plan.fetch(:scope_zones)).freeze
          @choice_path = DeepCopy.call(plan.fetch(:choice_path)).freeze
          @piece_paths = DeepCopy.call(plan.fetch(:piece_paths)).freeze
          @changes = DeepCopy.call(plan.fetch(:changes)).freeze
          @affected = @changes.map do |entry|
            after = entry.fetch(:after)
            { "kind" => "face", "id" => after.fetch("id"), "change" => "updated",
              "reference" => entry.fetch(:reference).merge("entity_id" => after.fetch("id")) }
          end
        end

        def descriptor
          { "name" => "repair_split_face", "zone" => @zone, "old_id" => @old_id,
            "scope_zones" => @scope_zones,
            "choice_path" => @choice_path,
            "piece_paths" => @piece_paths, "changes" => @changes }
        end

        def temporary_ids
          @changes.map { |entry| entry.fetch(:after).fetch("id") }.reject { |id| id == @old_id }
        end

        def apply(model, _slots)
          zone = Occurrences.resolve_zone(model, @zone, :mutable => true)
          SplitIdentityRepair.refuse_locked!(zone)
          present = Occurrences.faces(zone).select do |piece|
            Faces::FACE_STORE.read(piece.entity)&.fetch("id", nil) == @old_id
          end.map(&:path).sort
          global = SplitIdentityRepair.live_identity_counts(model.entities, @old_id)
          unless present == @piece_paths.sort && global.fetch(:ids) == @piece_paths.length
            raise CodedError.new("target.changed", "The split Face set changed after preview.")
          end

          resolved = @changes.map do |entry|
            reference = entry.fetch(:reference)
            occurrence = if reference.fetch("zone_path") == @zone.fetch("zone_path")
                           Occurrences.face_at(zone, reference.fetch("entity_path"), :mutable => true)
                         else
                           Occurrences.resolve_face(model, reference, :mutable => true)
                         end
            before = Faces::FACE_STORE.read(occurrence.entity)
            unless before == entry.fetch(:before)
              raise CodedError.new("target.changed", "A Face changed after the repair preview.")
            end

            if entry.key?(:stamp)
              stamp = STAMP_STORE.read(occurrence.entity)
              SplitIdentityRepair.check_stamp!(stamp, zone)
              unless stamp == entry.fetch(:stamp)
                raise CodedError.new("target.changed", "A Face stamp changed after the repair preview.")
              end
            end
            [occurrence, entry.fetch(:after)]
          end
          resolved.each { |occurrence, after| Faces::FACE_STORE.write(occurrence.entity, after) }
        end
      end
    end
  end
end
