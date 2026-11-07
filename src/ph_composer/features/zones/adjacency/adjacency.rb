# frozen_string_literal: true

module PhComposer
  module Zones
    module Adjacency
      POINT_TOLERANCE_M = 0.0000254
      PLANE_TOLERANCE_M = 0.0000254
      NORMAL_ANGLE_TOLERANCE_DEGREES = 0.1
      PAIR_PATTERN = Records::Identity.pattern("adj")

      module_function

      # Everything one Solve would do, settled before a single write: which Faces pair, which cuts
      # each pairing needs, and every case reported instead of paired. Reading is unbounded and
      # writing is not, so a pairing that would touch a Zone outside the scope refuses the whole
      # operation rather than quietly widening what the user selected.
      Plan = Struct.new(:matches, :findings, :retirements, :partitions, keyword_init: true)

      def plan(model, references)
        index = Index.new(model)
        scope = references.map do |reference|
          Occurrences.resolve_zone(model, reference, :mutable => true, :index => index)
        end
        if scope.map(&:path).uniq.length != scope.length
          raise CodedError.new("target.same_zone", "Solve needs distinct Zone occurrences.")
        end

        sides = index.zones.to_h { |zone| [zone.path, candidates(zone, index)] }
        in_scope = scope.map(&:path)
        found = examine(sides, in_scope)
        matches, partitions = resolve_contested(found.fetch(:matches), found.fetch(:findings))
        kept = components(matches).select { |group| group.length == 1 }.flatten.select do |match|
          match.fetch(:overlap).kind == :full && current_pair?(match.fetch(:left), match.fetch(:right))
        end.flat_map { |match| [:left, :right].map { |name| face_key(match.fetch(name)) } }
        updates = retirement_updates(model, scope, kept, index)
        matches.each do |match|
          [:left, :right].each do |name|
            side = match.fetch(name)
            update = updates[face_key(side)]
            side[:record] = update.after if update
          end
        end
        Plan.new(:matches => matches, :findings => found.fetch(:findings),
                 :retirements => updates.values, :partitions => partitions)
      end

      # Retire every old pair not retained by this solve, even when its geometry no longer meets
      # any candidate. The detached after-records also become the input to any replacement pair.
      def retirement_updates(model, scope, kept, index)
        updates = {}
        authored_face_counts = {}
        scope.each do |zone|
          index.faces(zone).each do |occurrence|
            record = Faces::FACE_STORE.read(occurrence.entity)
            next unless record && record["boundary_condition"] == "Surface"

            reference = occurrence.reference(record.fetch("id"))
            key = Occurrences.key(reference)
            next if kept.include?(key) || updates.key?(key)

            Occurrences.resolve_face(model, reference, :mutable => true, :index => index)
            Faces::Schema.validate!(record)
            envelope = record.fetch("adjacency")
            stored_self = retirement_endpoint(model, envelope.fetch("self"), index, authored_face_counts)
            unless stored_self && stored_self.zone.path == occurrence.zone.path &&
                   stored_self.path == occurrence.path && stored_self.entity.equal?(occurrence.entity)
              raise CodedError.new("adjacency.unresolved", "The Surface endpoint no longer matches its stored path.")
            end

            counterpart = retirement_endpoint(model, envelope.fetch("counterpart"), index, authored_face_counts)
            counts = authored_face_counts[:all]
            if counts && counts.fetch(record.fetch("id"), 0) != 1
              raise CodedError.new("target.ambiguous", "The Surface Face id occurs more than once.")
            end

            if counterpart
              check_retirement_pair!(occurrence, record, counterpart, scope.map(&:path), updates,
                                     authored_face_counts)
            end
            updates[key] = FaceRecordUpdate.new(:reference => reference, :before => record, :after => retired(record))
          end
        end
        updates
      end

      def check_retirement_pair!(occurrence, record, counterpart, in_scope, updates, authored_face_counts)
        other = Faces::FACE_STORE.read(counterpart.entity)
        Faces::Schema.validate!(other)
        other_reference = counterpart.reference(other.fetch("id"))
        unless reciprocal?(record, other)
          raise CodedError.new("adjacency.unresolved", "The reciprocal Surface endpoint cannot be retired safely.")
        end

        counts = authored_face_counts[:all]
        if counts && counts.fetch(other.fetch("id"), 0) != 1
          raise CodedError.new("target.ambiguous", "A Surface Face id occurs more than once.")
        end

        check_scope!({ :occurrence => occurrence }, { :occurrence => counterpart }, in_scope)
        updates[Occurrences.key(other_reference)] = FaceRecordUpdate.new(:reference => other_reference,
                                                                         :before => other, :after => retired(other))
      end

      # Only an explicit Solve can rebind an old adjacency path. The Zone and Face authored ids
      # must each identify one live occurrence, and the normal mutable resolver checks its actual
      # path before the proposal uses it. Geometry never selects a candidate.
      def retirement_endpoint(model, reference, index, authored_face_counts)
        Occurrences.resolve_face(model, reference, :mutable => true, :index => index)
      rescue CodedError => error
        raise unless %w[target.changed target.not_found target.wrong_kind].include?(error.code)

        zones = index.zones.select { |zone| zone.record.fetch("id") == reference.fetch("zone_id") }
        raise CodedError.new("target.ambiguous", "The Surface Zone id occurs more than once.") if zones.length > 1

        face_id = reference.fetch("entity_id")
        authored_face_counts[:all] ||= face_id_occurrence_counts(model.entities)
        face_count = authored_face_counts.fetch(:all).fetch(face_id, 0)
        raise CodedError.new("target.ambiguous", "The Surface Face id occurs more than once.") if face_count > 1

        candidates = index.faces_with_id(face_id)
        if zones.empty? || candidates.empty?
          if endpoint_survives?(model.entities, reference)
            raise CodedError.new("adjacency.unresolved", "The Surface endpoint survives outside its stored path.")
          end

          return nil
        end
        unless candidates.length == 1 && candidates.first.zone.path == zones.first.path && face_count == 1
          raise CodedError.new("adjacency.unresolved", "The Surface endpoint is not in its authored Zone.")
        end

        Occurrences.resolve_face(model, candidates.first.reference(face_id), :mutable => true, :index => index)
      end

      # Count even orphan Faces and repeated component occurrences; build this only on the first
      # path-recovery attempt and reuse it for the rest of the Solve plan.
      def face_id_occurrence_counts(entities, counts = Hash.new(0))
        entities.each do |entity|
          if entity.is_a?(Sketchup::Face)
            face_id = Faces::FACE_STORE.read(entity)&.fetch("id", nil)
            counts[face_id] += 1 if face_id
          elsif entity.is_a?(Sketchup::Group)
            face_id_occurrence_counts(entity.entities, counts)
          elsif entity.is_a?(Sketchup::ComponentInstance)
            face_id_occurrence_counts(entity.definition.entities, counts)
          end
        end
        counts
      end

      # A missing path may mean cut/paste or an exploded Zone, not deletion. Only the absence of
      # both the native Face id and its authored id throughout live geometry confirms deletion.
      def endpoint_survives?(entities, reference)
        entities.any? do |entity|
          if entity.is_a?(Sketchup::Face)
            entity.persistent_id == reference.fetch("entity_path").last ||
              Faces::FACE_STORE.read(entity)&.fetch("id", nil) == reference.fetch("entity_id")
          elsif entity.is_a?(Sketchup::Group)
            endpoint_survives?(entity.entities, reference)
          elsif entity.is_a?(Sketchup::ComponentInstance)
            endpoint_survives?(entity.definition.entities, reference)
          else
            false
          end
        end
      end
      private_class_method :retirement_updates, :check_retirement_pair!, :retirement_endpoint,
                           :face_id_occurrence_counts, :endpoint_survives?

      # Every cross-Zone Face pairing, classified. All Zones are read; the scope only limits writing.
      def examine(sides, in_scope)
        matches = []
        findings = []
        sides.keys.combination(2).each do |left_path, right_path|
          next unless in_scope.include?(left_path) || in_scope.include?(right_path)

          sides.fetch(left_path).each do |left|
            sides.fetch(right_path).each do |right|
              result = Overlap.between(left.fetch(:geometry), right.fetch(:geometry),
                                       :plane_tolerance_m => PLANE_TOLERANCE_M,
                                       :angle_tolerance_degrees => NORMAL_ANGLE_TOLERANCE_DEGREES,
                                       :point_tolerance_m => POINT_TOLERANCE_M)
              next if result.kind == :none

              unless result.paired?
                findings << reported(result, left, right)
                next
              end
              check_scope!(left, right, in_scope)
              matches << { :left => left, :right => right, :overlap => result }
            end
          end
        end
        { :matches => matches, :findings => findings }
      end

      # Making or retiring a pair writes both endpoints, so both Zones must be in the mutation set.
      # Refusing names both, so the caller can offer a retry that includes them.
      def check_scope!(left, right, in_scope)
        outside = [left, right].map { |side| side.fetch(:occurrence).zone }
                               .reject { |zone| in_scope.include?(zone.path) }
        return if outside.empty?

        raise CodedError.new(
          "scope.incomplete",
          "Updating this adjacency would change #{outside.map { |zone| zone.record.fetch('name') }.join(' and ')}, " \
          "which is outside the Zones being solved. Include both Zones and solve again.",
          "zones" => [left, right].map { |side| side.fetch(:occurrence).zone.reference }
        )
      end

      # Match components share original Faces. Accept a component only when every original Face
      # has a complete, disjoint partition; otherwise none of its pairs is written.
      def resolve_contested(matches, findings)
        accepted = []
        partitions = {}
        components(matches).each do |group|
          if group.length == 1
            accepted.concat(group)
            next
          end

          # Each original Face in the component, with every shared region the component cuts from it.
          cuts = group.flat_map do |match|
            [:left, :right].map { |name| { :side => match.fetch(name), :polygon_m => match.fetch(:overlap).polygon_m } }
          end
          group_partitions = cuts.group_by { |cut| face_key(cut.fetch(:side)) }.to_h do |key, face_cuts|
            geometry = face_cuts.first.fetch(:side).fetch(:geometry)
            [key, Overlap.partition(geometry, face_cuts.map { |cut| cut.fetch(:polygon_m) })]
          end
          if group_partitions.values.any?(&:nil?)
            findings << multiple_neighbours(group)
          else
            accepted.concat(group)
            partitions.merge!(group_partitions)
          end
        end
        [accepted, partitions]
      end

      def components(matches)
        remaining = matches.dup
        result = []
        until remaining.empty?
          group = [remaining.shift]
          keys = match_keys(group.first)
          loop do
            connected, remaining = remaining.partition { |match| match_keys(match).any? { |key| keys.include?(key) } }
            break if connected.empty?

            group.concat(connected)
            keys.concat(connected.flat_map { |match| match_keys(match) })
          end
          result << group
        end
        result
      end

      def face_key(side)
        Occurrences.key(side.fetch(:occurrence).reference)
      end

      # The two Faces a match joins, as occurrence keys.
      def match_keys(match)
        [face_key(match.fetch(:left)), face_key(match.fetch(:right))]
      end

      def multiple_neighbours(group)
        zones = group.flat_map { |match| [:left, :right].map { |side| match.fetch(side).fetch(:occurrence).zone } }
        {
          "code" => "adjacency.multiple_neighbours", "severity" => "warning",
          "zones" => zones.map(&:reference).uniq,
          "message" => "A Face meets more than one neighbour and was not cut. Zones: " \
                       "#{zones.map { |zone| zone.record.fetch('name') }.uniq.join(', ')}."
        }
      end

      REPORTED_CODES = {
        :same_normal => "adjacency.overlapping_zones",
        :sliver => "adjacency.sliver_skipped",
        :unsupported => "adjacency.unsupported_shape",
        :glued_instances => "adjacency.glued_instances"
      }.freeze

      def reported(result, left, right)
        zones = [left, right].map { |side| side.fetch(:occurrence).zone }
        names = zones.map { |zone| zone.record.fetch("name") }
        {
          "code" => REPORTED_CODES.fetch(result.kind), "severity" => "warning",
          "zones" => zones.map(&:reference), "area_m2" => result.area_m2,
          "message" => message_for(result, names)
        }.compact
      end

      def message_for(result, names)
        case result.kind
        when :same_normal
          "#{names.join(' and ')} overlap: these coplanar Faces point the same way, so neither is a " \
          "boundary of the other."
        when :sliver
          "A shared region between #{names.join(' and ')} was skipped because #{result.reason}."
        else
          "A shared region between #{names.join(' and ')} was not cut because #{result.reason}."
        end
      end

      def pair(left, right)
        left_record = left.fetch(:record)
        right_record = right.fetch(:record)
        existing = [left_record, right_record].select { |record| record["boundary_condition"] == "Surface" }
        unless existing.empty?
          return [left_record, right_record, left_record.dig("adjacency", "pair_id")] if current_pair?(left, right)

          raise CodedError.new("adjacency.stale", "Retire the existing Surface pair before solving again.")
        end

        pair_id = pair_id_for(left, right)
        Faces::AssemblyAssignment.settle_new_pair!(with_pair(left, right, pair_id), with_pair(right, left, pair_id)) +
          [pair_id]
      end

      # A pair's id derives from its two Face ids alone, in either order, so a full match, a cut and a
      # partition all name the same pair the same way.
      def pair_id_for(left, right)
        Records::Identity.derived("adj", "faces" => [left, right].map { |side| side.fetch(:record).fetch("id") }.sort)
      end

      def state(model, occurrence, record, index: nil)
        return nil unless record && record["boundary_condition"] == "Surface"

        envelope = record["adjacency"]
        return "invalid" unless envelope.is_a?(Hash)

        self_reference = envelope.fetch("self")
        counterpart_reference = envelope.fetch("counterpart")
        self_occurrence = Occurrences.resolve_face(model, self_reference, :index => index)
        return "unresolved" unless self_occurrence.entity.equal?(occurrence.entity) &&
                                   self_reference == occurrence.reference(record.fetch("id"))

        counterpart = Occurrences.resolve_face(model, counterpart_reference, :index => index)
        other_record = Faces::FACE_STORE.read(counterpart.entity)
        return "unresolved" unless other_record && reciprocal?(record, Faces::Schema.validate!(other_record))

        digests = [occurrence, counterpart].map { |side| FaceCapture.call(side.entity, side.transform).digest }
        geometry_current?(record, other_record, *digests) ? "current" : "stale"
      rescue CodedError
        "unresolved"
      end

      # The detached form of `state` for export: the same reciprocal and geometry rules, with each
      # record's own endpoint compared against the snapshot path instead of a live occurrence.
      def snapshot_pair_current?(left_entry, left_record, right_entry, right_record)
        reciprocal?(left_record, right_record) &&
          endpoint_path(left_record.dig("adjacency", "self")) == left_entry.path &&
          endpoint_path(right_record.dig("adjacency", "self")) == right_entry.path &&
          geometry_current?(left_record, right_record, left_entry.geometry.digest, right_entry.geometry.digest)
      end

      # Whether two Face records are the two ends of one Surface pair: both Surface, one pair id, and
      # each naming the other as its counterpart exactly as the other names itself. It reads only the
      # records; where each end lives now is the caller's to compare, live or detached.
      def reciprocal?(left_record, right_record)
        left = left_record["adjacency"]
        right = right_record["adjacency"]
        left_record["boundary_condition"] == "Surface" && right_record["boundary_condition"] == "Surface" &&
          left.is_a?(Hash) && right.is_a?(Hash) && left["pair_id"] == right["pair_id"] &&
          left["self"] == right["counterpart"] && left["counterpart"] == right["self"] &&
          left.dig("counterpart", "entity_id") == right_record["id"] &&
          right.dig("counterpart", "entity_id") == left_record["id"]
      end

      # Whether both ends' geometry stamps, of themselves and of each other, match these digests.
      def geometry_current?(left_record, right_record, left_digest, right_digest)
        left = left_record["adjacency"]
        right = right_record["adjacency"]
        left.dig("self_geometry", "digest") == left_digest &&
          left.dig("counterpart_geometry", "digest") == right_digest &&
          right.dig("self_geometry", "digest") == right_digest &&
          right.dig("counterpart_geometry", "digest") == left_digest
      end
      private_class_method :geometry_current?

      # The two FaceRecordUpdates that retire a Surface pair: this Face's, then its counterpart's.
      def retirement_pair(model, occurrence, record, index: nil)
        unless record && record["boundary_condition"] == "Surface" && record["adjacency"].is_a?(Hash)
          raise CodedError.new("adjacency.not_surface", "That Face has no Surface pair to retire.")
        end

        counterpart = Occurrences.resolve_face(model, record.fetch("adjacency").fetch("counterpart"),
                                               :mutable => true, :index => index)
        other = Faces::FACE_STORE.read(counterpart.entity)
        unless other && reciprocal?(record, other)
          raise CodedError.new("adjacency.unresolved", "The reciprocal Surface endpoint cannot be retired safely.")
        end

        [FaceRecordUpdate.new(:reference => occurrence.reference(record.fetch("id")), :before => record,
                              :after => retired(record)),
         FaceRecordUpdate.new(:reference => counterpart.reference(other.fetch("id")), :before => other,
                              :after => retired(other))]
      end

      def validate_envelope(envelope)
        return ["adjacency must be an object"] unless envelope.is_a?(Hash)

        required = %w[schema_version pair_id self counterpart self_geometry counterpart_geometry]
        found = required.reject { |key| envelope.key?(key) }.map { |key| "adjacency is missing #{key}" }
        found << "adjacency schema_version must be 1" unless envelope["schema_version"] == 1
        found << "adjacency pair_id is invalid" unless PAIR_PATTERN.match?(envelope["pair_id"].to_s)
        %w[self counterpart].each do |key|
          found << "adjacency #{key} endpoint is invalid" unless valid_endpoint?(envelope[key])
        end
        %w[self_geometry counterpart_geometry].each do |key|
          geometry = envelope[key]
          valid = geometry.is_a?(Hash) && geometry["digest"].to_s.start_with?("sha256:") &&
                  geometry["area_m2"].is_a?(Numeric) && geometry["area_m2"].finite?
          found << "adjacency #{key} is invalid" unless valid
        end
        found
      end

      def candidates(zone, index)
        index.faces(zone).filter_map do |occurrence|
          record = Faces::FACE_STORE.read(occurrence.entity)
          next unless record && record["face_type"]

          Faces::Schema.validate!(record)
          { :occurrence => occurrence, :record => record,
            :geometry => FaceCapture.call(occurrence.entity, occurrence.transform) }
        end
      end
      private_class_method :examine, :check_scope!, :resolve_contested, :face_key,
                           :multiple_neighbours, :reported, :message_for
      private_class_method :candidates

      def current_pair?(left, right)
        left_record = left.fetch(:record)
        right_record = right.fetch(:record)
        left_reference = left.fetch(:occurrence).reference(left_record.fetch("id"))
        right_reference = right.fetch(:occurrence).reference(right_record.fetch("id"))
        reciprocal?(left_record, right_record) &&
          left_record.dig("adjacency", "self") == left_reference &&
          right_record.dig("adjacency", "self") == right_reference &&
          geometry_current?(left_record, right_record, left.fetch(:geometry).digest, right.fetch(:geometry).digest)
      end
      private_class_method :current_pair?

      def with_pair(side, counterpart, pair_id)
        result = DeepCopy.call(side.fetch(:record))
        result["boundary_condition"] = "Surface"
        result.delete("attached_zone_id")
        result["adjacency"] = {
          "schema_version" => 1, "pair_id" => pair_id,
          "self" => side.fetch(:occurrence).reference(side.fetch(:record).fetch("id")),
          "counterpart" => counterpart.fetch(:occurrence).reference(counterpart.fetch(:record).fetch("id")),
          "self_geometry" => geometry_stamp(side.fetch(:geometry)),
          "counterpart_geometry" => geometry_stamp(counterpart.fetch(:geometry))
        }
        Faces::Schema.validate!(result)
      end
      private_class_method :with_pair

      def geometry_stamp(geometry)
        { "digest" => geometry.digest, "area_m2" => geometry.area_m2 }
      end
      private_class_method :geometry_stamp

      def retired(record)
        result = Faces::Schema.leave_pair!(DeepCopy.call(record))
        result.delete("boundary_condition")
        Faces::Schema.validate!(result)
      end
      private_class_method :retired

      def valid_endpoint?(value)
        value.is_a?(Hash) && %w[zone_id zone_path entity_path entity_id].all? { |key| value.key?(key) } &&
          value["zone_id"].is_a?(String) && value["zone_path"].is_a?(Array) &&
          value["entity_path"].is_a?(Array) && value["entity_id"].is_a?(String)
      end
      private_class_method :valid_endpoint?

      def endpoint_path(endpoint)
        return [] unless endpoint.is_a?(Hash)

        Array(endpoint["zone_path"]) + Array(endpoint["entity_path"])
      end
      private_class_method :endpoint_path
    end
  end
end
