# frozen_string_literal: true

module PhComposer
  module Zones
    module Faces
      # The Attached zone record writes, which also move the Faces naming a record: save, create and
      # assign in one step, and delete with replacement. Each only reads and proposes; the dispatcher
      # owns the native operation.

      module_function

      # Without `id` it creates a record, with `user_data` if given; with it, `values` patches that record and
      # its metadata stays as stored, written only through ph_composer.records.update_metadata.
      def save_attached_zone(request, proposal, values:, id: nil, expected_values: {}, user_data: nil)
        patch = values
        if id
          unless user_data.nil?
            raise CodedError.new("params.invalid", "An Attached zone edit does not take user_data; write it with " \
                                                   "ph_composer.records.update_metadata. Nothing was written.")
          end

          # `values` is a partial patch, so the findings have to read the record the save will leave
          # behind. Reading the patch alone drops the low-factor warning on every edit that does not
          # happen to name the factor.
          values = merged_values(request.engine.kind(AttachedZone::KIND_ID)
                                   .values(request.engine.find(AttachedZone::KIND_ID, id)), patch)
          request.engine.propose_update(AttachedZone::KIND_ID, id, proposal,
                                        :values => patch, :expected_values => expected_values)
        else
          values = { "temperature_reduction_factor" => AttachedZone::DEFAULT_FACTOR }.merge(patch)
          id = request.engine.propose_create(AttachedZone::KIND_ID, proposal, :values => values,
                                                                              :user_data => user_data)
        end
        AttachedZone.findings(values.merge("id" => id)).each { |finding| proposal.add_finding(finding) }
        { "id" => id }
      end

      # The record proposal and the complete Face proposal are validated before the dispatcher
      # opens its native operation. ClassifyStep then writes the Faces, followed by the staged record
      # write; a host failure rolls both back. The new id is frozen into preview's normalized digest.
      def create_and_assign_attached_zone(request, proposal, values:, faces:, intent: {}, expected_values: {},
                                          user_data: nil)
        created = save_attached_zone(request, proposal, :values => values, :user_data => user_data)
        id = created.fetch("id")
        intent = intent.merge(
          "boundary_condition" => { "mode" => "set", "value" => "AttachedZone" },
          "attached_zone_id" => { "mode" => "set", "value" => id }
        )
        classified = plan_classification(request, proposal, faces, intent, expected_values)
        created.merge(classified)
      end

      # The engine's own patch rule: a named value replaces, and an explicit nil removes.
      def merged_values(before, patch)
        patch.each_with_object(DeepCopy.call(before)) do |(key, value), after|
          value.nil? ? after.delete(key) : after[key] = DeepCopy.call(value)
        end
      end

      # Delete with replacement, in one proposal: every Face naming the record moves first, then the
      # record goes. A Face the caller cannot reach refuses the whole delete, naming the routes. The
      # engine's own reference check sees every Face through the Face descriptor and reads the planned
      # reassignment, so it is the backstop for any other caller.
      def delete_attached_zone(request, proposal, id:, replacement:)
        request.engine.find(AttachedZone::KIND_ID, id)
        validate_replacement!(request, replacement, id)

        updates = reassignable_faces(request.model, id).map do |occurrence, record|
          after = DeepCopy.call(record)
          if replacement.fetch("mode") == "attached_zone"
            after["attached_zone_id"] = replacement.fetch("attached_zone_id")
          else
            after.delete("attached_zone_id")
            after["boundary_condition"] = replacement.fetch("boundary_condition")
          end
          { "reference" => occurrence.reference(record.fetch("id")), "before" => record,
            "after" => Schema.validate!(after), "stamp" => nil, "change" => "updated" }
        end
        unless updates.empty?
          scopes = updates.map do |update|
            Operations::EntityScope.new(update.fetch("reference").fetch("zone_path")[0...-1])
          end
          proposal.add_step(ClassifyStep.new(:updates => updates), :scopes => scopes)
        end
        removed = request.engine.propose_delete(AttachedZone::KIND_ID, id, proposal,
                                                :reference_plan => reassignment_plan(updates))
        { "id" => id, "reassigned_faces" => updates.length }.merge(removed)
      end

      def validate_replacement!(request, replacement, deleted_id)
        return unless replacement.fetch("mode") == "attached_zone"

        target = replacement["attached_zone_id"]
        if target.to_s.empty?
          raise CodedError.new("params.invalid", "A replacement Attached zone needs attached_zone_id.")
        end
        if target == deleted_id
          raise CodedError.new("params.invalid", "The replacement cannot be the Attached zone being deleted.")
        end

        request.engine.find(AttachedZone::KIND_ID, target)
      end

      # Every Face naming the record, found through the orphan-inclusive inventory, must be one a
      # normal Classify could rewrite: inside a Zone and resolvable for mutation. A Face exploded or
      # moved out of every Zone, or held in storage another placement shares, is never rewritten from
      # here; the delete refuses and names it.
      def reassignable_faces(model, attached_zone_id)
        reasons = {}
        reachable = referencing_faces(model, attached_zone_id).select do |occurrence, record|
          Zones::Occurrences.resolve_face(model, occurrence.reference(record.fetch("id")), :mutable => true)
        rescue CodedError => error
          reasons[occurrence.zone.path + occurrence.path] = error.code
          false
        end
        keys = reachable.map { |occurrence, _record| occurrence.zone.path + occurrence.path }
        stranded = ReferenceTargets.entries(model).select do |entry|
          entry.record["attached_zone_id"] == attached_zone_id && !keys.include?(entry.key)
        end
        refuse_stranded!(model, attached_zone_id, stranded, reasons) unless stranded.empty?
        reachable
      end

      def referencing_faces(model, attached_zone_id)
        Zones::Occurrences.zones(model).flat_map { |zone| Zones::Occurrences.faces(zone) }.filter_map do |occurrence|
          record = FACE_STORE.read(occurrence.entity)
          [occurrence, record] if record && record["attached_zone_id"] == attached_zone_id
        end
      end

      def refuse_stranded!(model, attached_zone_id, entries, reasons)
        faces = entries.map do |entry|
          { "id" => entry.record.fetch("id"), "path" => entry.key,
            "reason" => reasons.fetch(entry.key) { Faces.stranded_reason(model, entry.key) } }
        end
        routes = faces.map { |face| STRANDED_ROUTES.fetch(face.fetch("reason"), "resolve its #{face.fetch('reason')}") }
        raise CodedError.new(
          "reference.in_use",
          "#{faces.length} Face(s) still use Attached zone #{attached_zone_id} where this delete cannot " \
          "reach them. For each, #{routes.uniq.join('; or ')}, then delete again.",
          "target_kind" => AttachedZone::KIND_ID, "id" => attached_zone_id, "faces" => faces
        )
      end
    end
  end
end
