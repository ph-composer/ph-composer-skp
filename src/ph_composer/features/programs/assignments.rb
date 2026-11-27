# frozen_string_literal: true

module PhComposer
  module Programs
    # The per-Zone assignment actions: a Program, a Dwelling, a Zone's counts and an Equipment Set, each one Undo
    # step. Every Zone payload goes through Zones' `stage_extension` participant, so no Zone record is written
    # here. Each takes its inputs as arguments, so a library assignment can call the same operation.
    #
    # Each refuses what the generic metadata routes only report (context/CONTRACTS.md, "Occupancy"): a Zone of a
    # Segment that is a single dwelling, where the setting decides (`programs.single_dwelling`), and a Dwelling whose
    # Zones would lie in two Segments (`programs.dwelling_across_segments`). A Dwelling no Zone names afterwards is
    # deleted in the same step, and the maps it held are reported as any delete reports them.
    module Assignments
      STAGE = Zones::ExtensionStaging::NAME
      SINGLE = "programs.single_dwelling"
      ACROSS = "programs.dwelling_across_segments"
      CHOICES = %w[shared each none existing].freeze

      module_function

      # Sets the Program of each Zone; null returns it to its Segment's default.
      def assign_program(request, proposal, zones:, program_id:)
        state = OccupancyState.read(request)
        targets = targets!(state, zones)
        program_id = stored_id!(request, proposal, PROGRAM_KIND, program_id)
        stage(request, proposal, targets.to_h { |zone| [zone, zone.assignment.merge("program_id" => program_id)] })
        { "zone_ids" => targets.map(&:id), "program_id" => program_id }
      end

      # Puts each Zone in one new Dwelling (shared), one new Dwelling each (each), no Dwelling (none), or the named
      # one (existing). A Zone joining a Dwelling leaves its own Equipment Set to the Dwelling; one leaving every
      # Dwelling leaves its counts, which count only within one. New Dwellings take the first Zone's name.
      def assign_dwelling(request, proposal, zones:, choice:, dwelling_id: nil)
        unless CHOICES.include?(choice) && (choice == "existing") == !dwelling_id.nil?
          raise CodedError.new("params.invalid", "Choose shared, each or none, or existing with a dwelling_id.")
        end

        state = OccupancyState.read(request)
        targets = targets!(state, zones)
        Store.find(request, DWELLING_KIND, dwelling_id) if dwelling_id
        ids = dwelling_ids(request, proposal, targets, choice, dwelling_id)
        payloads = targets.zip(ids).to_h do |zone, id|
          leaving = id.nil? ? { "bedrooms" => nil, "occupants" => nil } : { "equipment_set_id" => nil }
          [zone, zone.assignment.merge("dwelling_id" => id).merge(leaving)]
        end
        check_segments!(state, payloads)
        entries = stage(request, proposal, payloads)
        removed, report = delete_emptied(request, proposal, state, payloads, entries)
        { "zone_ids" => targets.map(&:id), "dwelling_ids" => ids.compact.uniq,
          "deleted_dwelling_ids" => removed }.merge(report)
      end

      # The Dwelling each target joins, creating the new ones.
      def dwelling_ids(request, proposal, targets, choice, dwelling_id)
        case choice
        when "existing" then targets.map { dwelling_id }
        when "none" then targets.map { nil }
        when "shared"
          id = create_dwelling(request, proposal, targets.map(&:name).compact.min || "Dwelling")
          targets.map { id }
        else targets.map { |zone| create_dwelling(request, proposal, zone.name || "Dwelling") }
        end
      end

      # One Zone's bedrooms and occupants; the Zone must be in a Dwelling, where they count.
      def set_counts(request, proposal, zone:, bedrooms:, occupants:)
        state = OccupancyState.read(request)
        target = targets!(state, [zone]).first
        if target.assignment.fetch("dwelling_id").nil?
          raise CodedError.new("validation.failed",
                               "#{Records::Names.titled('Zone',
                                                        target.name)} is in no Dwelling, so it holds no counts.")
        end

        stage(request, proposal, { target => target.assignment.merge("bedrooms" => bedrooms,
                                                                     "occupants" => occupants) })
        { "zone_id" => target.id }
      end

      # An Equipment Set, or null for the Model's default, on Dwellings and on Zones that are not in a Dwelling.
      def assign_equipment_set(request, proposal, equipment_set_id:, dwelling_ids: [], zones: [])
        raise CodedError.new("params.invalid", "Name a Dwelling or a Zone.") if dwelling_ids.empty? && zones.empty?

        state = OccupancyState.read(request)
        targets = zones.empty? ? [] : targets!(state, zones)
        in_dwelling = targets.find { |zone| zone.assignment.fetch("dwelling_id") }
        if in_dwelling
          raise CodedError.new("validation.failed", "#{Records::Names.titled('Zone', in_dwelling.name)} is in a " \
                                                    "Dwelling; its Equipment Set is the Dwelling's.")
        end

        set_id = stored_id!(request, proposal, EQUIPMENT_SET_KIND, equipment_set_id)
        dwelling_ids.uniq.each do |id|
          before = Store.find(request, DWELLING_KIND, id, :proposal => proposal)
          next if before["equipment_set_id"] == set_id

          request.engine.propose_update(DWELLING_KIND, id, proposal, :values => { "equipment_set_id" => set_id })
        end
        stage(request, proposal, targets.to_h { |zone| [zone, zone.assignment.merge("equipment_set_id" => set_id)] })
        { "dwelling_ids" => dwelling_ids.uniq, "zone_ids" => targets.map(&:id), "equipment_set_id" => set_id }
      end

      # Payload keys naming a Program or an Equipment Set: on Zones, then on Segments.
      RETARGETED = { PROGRAM_KIND => [%w[program_id], %w[default_program_id]],
                     EQUIPMENT_SET_KIND => [%w[equipment_set_id], %w[equipment_set_id]] }.freeze

      # Inside a Program's or Equipment Set's delete with a replacement: every Zone assignment and Segment setting
      # naming `from` names `to` instead, staged through Zones in the delete's proposal. Answers the changed Zones as
      # reference entries, which the delete's plan projects, as Zones are not this feature's to retarget (Dwellings
      # move through their own retargeter).
      def retarget(request, proposal, kind, from:, to:)
        zone_keys, segment_keys = RETARGETED.fetch(kind)
        state = OccupancyState.read(request, :proposal => proposal)
        zones = state.zones.filter_map do |zone|
          payload = renamed(zone.assignment, zone_keys, from, to)
          { "reference" => zone.reference, "payload" => payload } if payload
        end
        segments = state.segments.filter_map do |segment|
          payload = segment.stored && renamed(segment.settings, segment_keys, from, to)
          { "id" => segment.id, "payload" => payload } if payload
        end
        unless segments.empty?
          request.participate(STAGE, "namespace" => Occupancy::SEGMENT_NAMESPACE, "segments" => segments)
        end
        return [] if zones.empty?

        request.participate(STAGE, "namespace" => Occupancy::ZONE_NAMESPACE, "zones" => zones).fetch("zone_entries")
      end

      def renamed(payload, keys, from, to)
        hits = keys.select { |key| payload[key] == from }
        hits.empty? ? nil : payload.merge(hits.to_h { |key| [key, to] })
      end

      # ---------------------------------------------------------------- shared steps

      # The Zones `references` name, each resolved once, none in a single-dwelling Segment.
      def targets!(state, references)
        ids = references.map { |reference| reference.fetch("zone_id") }
        raise CodedError.new("params.invalid", "A Zone may appear only once.") if ids.uniq.length != ids.length

        references.map do |reference|
          zone = state.zone(reference.fetch("zone_id"))
          raise CodedError.new("target.not_found", "Zone #{reference.fetch('zone_id')} does not exist.") unless zone
          raise CodedError.new("target.changed", "The Zone occurrence path has changed.") unless
            zone.reference.fetch("zone_path") == reference.fetch("zone_path")

          segment = state.segment(zone.segment_id)
          if segment&.single?
            raise CodedError.new(SINGLE, "#{zone.name} is in #{segment.name}, a single dwelling: switch Single " \
                                         "dwelling off in its settings to assign its Zones.",
                                 "building_segment_id" => segment.id)
          end
          zone
        end
      end

      # `id` as a stored record of `kind`: an unwritten default is written first, so the payload can name it.
      def stored_id!(request, proposal, kind, id)
        return nil if id.nil?

        Store.find(request, kind, id, :proposal => proposal)
        Store.materialize!(request, proposal, [[kind, id]])
        id
      end

      # Stages each Zone's payload through Zones; answers the changed Zones as reference entries.
      def stage(request, proposal, payloads)
        zones = payloads.map { |zone, payload| { "reference" => zone.reference, "payload" => payload } }
        return [] if zones.empty?

        request.participate(STAGE, "namespace" => Occupancy::ZONE_NAMESPACE, "zones" => zones)
               .fetch("zone_entries")
      end

      # Refuses a Dwelling the targets join whose Zones, after `payloads`, lie in more than one Segment (no Segment
      # counts as one). A Dwelling the action does not join is left to the findings, so one already across Segments
      # never blocks repairing it.
      def check_segments!(state, payloads)
        after = state.zones.to_h { |zone| [zone.id, zone.assignment.fetch("dwelling_id")] }
        payloads.each { |zone, payload| after[zone.id] = payload.fetch("dwelling_id") }
        joined = payloads.values.map { |payload| payload.fetch("dwelling_id") }.compact.uniq
        state.zones.group_by { |zone| after.fetch(zone.id) }.each do |dwelling_id, members|
          next if !joined.include?(dwelling_id) || members.map(&:segment_id).uniq.length < 2

          name = state.dwelling(dwelling_id)&.fetch("name") || "The new Dwelling"
          raise CodedError.new(ACROSS, "#{name} would hold Zones in two Building Segments; a Dwelling lies in one.",
                               "dwelling_id" => dwelling_id)
        end
      end

      def create_dwelling(request, proposal, stem)
        Operations.create(request, proposal, DWELLING_KIND,
                          :values => { "name" => free_name(request, stem, :proposal => proposal) }).fetch("id")
      end

      # `stem`, or "<stem> 2" and on while another Dwelling, stored or created in `proposal`, has the name.
      def free_name(request, stem, proposal: nil)
        staged = proposal ? proposal.writes.select { |write| write.kind == DWELLING_KIND && write.after } : []
        rows = Store.names(request, DWELLING_KIND) + staged.map(&:after)
        taken = rows.map { |row| Records::Names.key(row.fetch("name")) }
        (1..).each do |index|
          candidate = index == 1 ? stem.strip : "#{stem.strip} #{index}"
          return candidate unless taken.include?(Records::Names.key(candidate))
        end
      end

      # Deletes each Dwelling the targets left that no Zone names afterwards. Its Zones' payloads are staged, so the
      # delete's reference check reads them through `entries` as the proposal leaves them.
      def delete_emptied(request, proposal, state, payloads, entries)
        after = state.zones.to_h { |zone| [zone.id, zone.assignment.fetch("dwelling_id")] }
        payloads.each { |zone, payload| after[zone.id] = payload.fetch("dwelling_id") }
        left = payloads.keys.map { |zone| zone.assignment.fetch("dwelling_id") }.compact.uniq
        emptied = left.reject { |id| after.value?(id) }
        delete_dwellings(request, proposal, emptied, entries)
      end

      def delete_dwellings(request, proposal, ids, entries)
        plan = Records::ReferencePlan.new(:entries => entries.map do |entry|
          Records::ReferenceEntry.new(:kind => entry.fetch("kind"), :key => entry.fetch("key"),
                                      :record => entry.fetch("record"))
        end)
        records = ids.sort.map do |id|
          record = request.engine.find(DWELLING_KIND, id, :change_set => proposal)
          request.engine.propose_delete(DWELLING_KIND, id, proposal, :reference_plan => plan)
          record
        end
        [ids.sort, Records::Metadata.removed_user_data(Dwelling::KIND, records)]
      end
    end
  end
end
