# frozen_string_literal: true

module PhComposer
  module Zones
    # The adjacency handlers the declarations register: Solve, retire one pair, and the retirement
    # plan Classify composes into its own step.

    module_function

    def solve_adjacency(request, proposal, zones:)
      plan = Adjacency.plan(request.model, zones)
      plan.findings.each { |finding| proposal.add_finding(finding) }
      unless plan.retirements.empty?
        proposal.add_step(FaceRecordStep.new(:updates => plan.retirements, :change => "retired"),
                          :scopes => record_scopes(plan.retirements))
      end
      unchanged = []
      pair_ids = Adjacency.components(plan.matches).flat_map do |group|
        if group.length > 1
          partition_matches(request, proposal, group, plan.partitions)
        elsif group.first.fetch(:overlap).kind == :full
          [pair_match(proposal, group.first, unchanged)]
        else
          [split_match(request, proposal, group.first)]
        end
      end
      { "pair_ids" => pair_ids.compact.sort, "already_paired" => unchanged.length,
        "reported" => proposal.findings.length }
    end

    def partition_matches(request, proposal, group, partitions)
      sides = {}
      matches = group.each_with_index.map do |match, index|
        check_unpaired!(match)
        positions = [:left, :right].map do |name|
          side = match.fetch(name)
          occurrence = side.fetch(:occurrence)
          key = Occurrences.key(occurrence.reference)
          sides[key] ||= { :side => side, :regions => [] }
          sides.fetch(key).fetch(:regions) << { "match_index" => index, "polygon_m" => match.fetch(:overlap).polygon_m }
          key
        end
        { "keys" => positions, "pair_id" => Adjacency.pair_id_for(match.fetch(:left), match.fetch(:right)) }
      end
      face_keys = sides.keys
      faces = face_keys.map do |key|
        item = sides.fetch(key)
        partition_side_plan(request, item.fetch(:side), item.fetch(:regions), partitions.fetch(key))
      end
      matches.each do |match|
        match["left"] = face_keys.index(match.fetch("keys").fetch(0))
        match["right"] = face_keys.index(match.fetch("keys").fetch(1))
        match.delete("keys")
      end
      scopes = faces.map { |face| Operations::EntityScope.new(face.fetch("reference").fetch("zone_path")) }
      step = PartitionAndPairStep.new(:faces => faces, :matches => matches, :catalog => request.registry.catalog)
      proposal.add_step(step, :scopes => scopes)
      matches.map { |match| match.fetch("pair_id") }
    end

    def partition_side_plan(request, side, regions, partition)
      occurrence = side.fetch(:occurrence)
      record = side.fetch(:record)
      complete = partition.fetch(:remainder_area_m2) <= 1.0e-7
      needs_cut = regions.length > 1 || !complete
      fresh = if needs_cut
                (regions.length + partition.fetch(:remainder_count)).times.map do |index|
                  Records::Identity.derived("fac", "model" => request.model.guid,
                                                   "revision" => request.revision,
                                                   "zone_path" => occurrence.zone.path,
                                                   "entity_path" => occurrence.path, "piece" => index)
                end
              else
                []
              end
      copies = {}
      if needs_cut
        data = record.fetch("extension_data", {})
        catalog = request.registry.catalog
        Records::Extension.check_copy_rules!(data, catalog, "Face", record.fetch("id"))
        fresh.each do |id|
          copies[id] = Records::Extension.copy_data(data, catalog, "Face", record.fetch("id"),
                                                    { record.fetch("id") => id },
                                                    :engine => request.engine,
                                                    :reference_plan => split_reference_plan(occurrence, record, id))
        end
      end
      { "reference" => occurrence.reference(record.fetch("id")), "before" => record,
        "persistent_id" => occurrence.entity.persistent_id, "fresh_ids" => fresh,
        "has_glued_instances" => side.fetch(:geometry).has_glued_instances,
        "extension_copies" => copies, "regions" => regions,
        "complete" => complete, "area_m2" => side.fetch(:geometry).area_m2,
        "remainder_area_m2" => partition.fetch(:remainder_area_m2) }
    end

    def split_reference_plan(occurrence, record, id)
      entry = Records::ReferenceEntry.new(
        :kind => Faces::REFERENCE_KIND,
        :key => occurrence.zone.path + occurrence.path + [id], :record => record.merge("id" => id)
      )
      Records::ReferencePlan.new(:entries => [entry])
    end

    # A partial overlap is cut on both sides and paired in one step, because the pair's endpoints
    # do not exist until both Faces have been cut.
    def split_match(request, proposal, match)
      overlap = match.fetch(:overlap)
      check_unpaired!(match)
      pair_id = Adjacency.pair_id_for(match.fetch(:left), match.fetch(:right))
      sides = [:left, :right].map do |name|
        side_plan(request, match.fetch(name), overlap, name == :left ? :left : :right)
      end
      scopes = sides.map { |side| Operations::EntityScope.new(side.fetch("reference").fetch("zone_path")) }
      proposal.add_step(
        SplitAndPairStep.new(:left => sides.fetch(0), :right => sides.fetch(1), :polygon_m => overlap.polygon_m,
                             :pair_id => pair_id, :catalog => request.registry.catalog),
        :scopes => scopes
      )
      pair_id
    end

    # The plan must retire an old Surface pair before proposing a cut, including its surviving
    # counterpart. Refuse an inconsistent plan rather than silently dropping one end of a pair.
    def check_unpaired!(match)
      paired = [:left, :right].select { |name| match.fetch(name).fetch(:record)["boundary_condition"] == "Surface" }
      return if paired.empty?

      raise CodedError.new("adjacency.stale",
                           "A Face that would be cut still holds a Surface pair. Retire it before solving again.")
    end

    # Ids for every piece the cut may need, allocated now so the preview digest is stable. Which
    # piece keeps the original id is the host's answer and is not known until it has cut.
    def side_plan(request, side, overlap, which)
      occurrence = side.fetch(:occurrence)
      record = side.fetch(:record)
      remainders = which == :left ? overlap.left_remainders_m : overlap.right_remainders_m
      fresh = (remainders.length + 1).times.map do |index|
        Records::Identity.derived("fac", "model" => request.model.guid, "revision" => request.revision,
                                         "zone_path" => occurrence.zone.path, "entity_path" => occurrence.path,
                                         "piece" => index)
      end
      copies = {}
      unless remainders.empty?
        data = record.fetch("extension_data", {})
        catalog = request.registry.catalog
        Records::Extension.check_copy_rules!(data, catalog, "Face", record.fetch("id"))
        fresh.each do |id|
          copies[id] = Records::Extension.copy_data(data, catalog, "Face", record.fetch("id"),
                                                    { record.fetch("id") => id },
                                                    :engine => request.engine,
                                                    :reference_plan => split_reference_plan(occurrence, record, id))
        end
      end
      { "reference" => occurrence.reference(record.fetch("id")), "before" => record,
        "persistent_id" => occurrence.entity.persistent_id, "fresh_ids" => fresh,
        "has_glued_instances" => side.fetch(:geometry).has_glued_instances,
        "remainder_count" => remainders.length, "extension_copies" => copies }
    end

    def pair_match(proposal, match, unchanged)
      left = match.fetch(:left)
      right = match.fetch(:right)
      left_after, right_after, pair_id = Adjacency.pair(left, right)
      if left_after == left.fetch(:record) && right_after == right.fetch(:record)
        unchanged << pair_id
        return pair_id
      end

      updates = [left, right].zip([left_after, right_after]).map do |side, after|
        record = side.fetch(:record)
        FaceRecordUpdate.new(:reference => side.fetch(:occurrence).reference(record.fetch("id")), :before => record,
                             :after => after)
      end
      proposal.add_step(FaceRecordStep.new(:updates => updates, :change => "updated"),
                        :scopes => record_scopes(updates))
      pair_id
    end

    def retire_adjacency(request, proposal, face:)
      occurrence = Occurrences.resolve_face(request.model, face, :mutable => true)
      record = Faces::FACE_STORE.read(occurrence.entity)
      pair_id = record&.dig("adjacency", "pair_id")
      retire_pair(request, proposal, occurrence, record)
      { "pair_id" => pair_id }
    end

    def retire_pair(request, proposal, occurrence, record)
      updates = Adjacency.retirement_pair(request.model, occurrence, record)
      proposal.add_step(FaceRecordStep.new(:updates => updates, :change => "retired"),
                        :scopes => record_scopes(updates))
      updates.first.after
    end

    # The Groups whose contents a set of Face record writes touch: each Face's Zone's parent.
    def record_scopes(updates)
      updates.map { |update| Operations::EntityScope.new(update.reference.fetch("zone_path")[0...-1]) }
    end

    # Plans the reciprocal retirement for a whole gesture without writing anything. The caller
    # composes the returned records into its own step, so Classify never edits an adjacency
    # envelope itself and one Face is written once even when both endpoints are being classified.
    #
    # Returns { occurrence key => FaceRecordUpdate } covering both targets and the counterparts they
    # drag in.
    def retire_pairs(request, targets, index = nil)
      plan = {}
      targets.each do |occurrence, record|
        Adjacency.retirement_pair(request.model, occurrence, record, :index => index).each do |update|
          add_retirement(plan, update)
        end
      end
      plan
    end

    def add_retirement(plan, update)
      key = Occurrences.key(update.reference)
      existing = plan[key]
      if existing && existing.after != update.after
        raise CodedError.new("gesture.retirement_conflict",
                             "Face #{update.before.fetch('id')} would be retired two different ways in one gesture.")
      end

      plan[key] = update
    end
    private_class_method :pair_match, :split_match, :check_unpaired!, :side_plan, :add_retirement, :record_scopes
  end
end
