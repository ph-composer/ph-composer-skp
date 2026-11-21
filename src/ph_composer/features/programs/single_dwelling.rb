# frozen_string_literal: true

module PhComposer
  module Programs
    # Single dwelling, switched in a Building Segment's settings (context/CONTRACTS.md, "Occupancy"). While it
    # applies (on, and the Segment residential) every Zone in the Segment is one dwelling with the residential
    # default, named for the Segment; its bedrooms, occupants and Equipment Set are the Segment's own settings, and
    # nothing is written to its Zones, so a Zone moved in joins without action.
    #
    # Zones' Save stages the settings; this feature's contributor to `ph_composer.zones.segment_settings_saved`
    # adds the side effects of the switch to the same Undo step, through Zones' participant for the Zones:
    #
    #   on    every Zone's assignment cleared (its Program, Dwelling, counts and Equipment Set), and each Dwelling
    #         no Zone then names deleted. The Save carries the house's counts: the section enters the Zones' summed
    #         bedrooms, from `preview`, for the user to see before saving.
    #   off   a Dwelling named for the Segment, holding the house's counts and Equipment Set, and every Zone in it
    #         with the default Program it had: no Program of its own, or the Model's default where the Segment
    #         names another.
    #
    # Only the switch itself has side effects, and only where it applies: on a residential Segment. A change of
    # category alone writes nothing; it changes whether the setting applies, and Zones keep their assignments.
    module SingleDwelling
      NAME = "#{FEATURE_ID}.single_dwelling"
      TRANSITION = Zones::Options::SegmentSettings::TRANSITION
      SEGMENT_KIND = Occupancy::SEGMENT_KIND
      REFUSES = (Zones::ExtensionStaging::REFUSES + %w[reference.in_use]).uniq.freeze

      module_function

      def install(feature)
        feature.transition_contributor(NAME, :transition => TRANSITION, :refuses => REFUSES) do |request, proposal,
                                                                                                 description|
          switch(request, proposal, description.fetch("building_segment_id"))
        end
      end

      # The side effects of one Save on its Segment; the Dwellings it created or deleted.
      def switch(request, proposal, id)
        write = proposal.find(SEGMENT_KIND, id)
        return [] unless write

        catalog = request.registry.catalog
        before = OccupancyState.segment(write.before, catalog)
        after = OccupancyState.segment(write.after, catalog)
        return [] if before.settings.fetch("single_dwelling") == after.settings.fetch("single_dwelling")

        if after.single?
          on(request, proposal, OccupancyState.read(request), after)
        elsif before.single? && after.category == "residential"
          off(request, proposal, OccupancyState.read(request), before, after)
        else
          []
        end
      end

      def on(request, proposal, state, segment)
        zones = state.zones_in(segment.id).reject { |zone| Occupancy.unassigned?(zone.assignment) }
        entries = Assignments.stage(request, proposal, zones.to_h { |zone| [zone, Occupancy::UNASSIGNED.dup] })
        named = state.zones.reject { |zone| zones.include?(zone) }.map { |zone| zone.assignment["dwelling_id"] }
        emptied = zones.map { |zone| zone.assignment["dwelling_id"] }.compact.uniq - named
        Assignments.delete_dwellings(request, proposal, emptied, entries).map do |dwelling_id|
          { "kind" => DWELLING_KIND, "id" => dwelling_id }
        end
      end

      # The house's counts and Set come from the Save when it sends them, else from the settings it replaced.
      def off(request, proposal, state, before, after)
        zones = state.zones_in(after.id)
        return [] if zones.empty?

        house = %w[bedrooms occupants equipment_set_id].to_h do |key|
          [key, after.settings[key].nil? ? before.settings[key] : after.settings[key]]
        end
        dwelling_id = Operations.create(request, proposal, DWELLING_KIND,
                                        :values => house.merge("name" => Assignments.free_name(request,
                                                                                               after.name,
                                                                                               :proposal => proposal)))
                                .fetch("id")
        program_id = after.settings["default_program_id"] && Assignments.stored_id!(
          request, proposal, PROGRAM_KIND, Settings.default_id(request.model, PROGRAM_KIND)
        )
        Assignments.stage(request, proposal, zones.to_h do |zone|
          [zone, Occupancy::UNASSIGNED.merge("program_id" => program_id, "dwelling_id" => dwelling_id)]
        end)
        [{ "kind" => DWELLING_KIND, "id" => dwelling_id }]
      end

      # What switching Single dwelling on in a Segment replaces, for the confirmation, and the bedrooms and occupants
      # it would hold: the Zones' summed counts, null where none holds one.
      def preview(state, segment_id)
        zones = state.zones_in(segment_id)
        assigned = zones.reject { |zone| Occupancy.unassigned?(zone.assignment) }
        dwellings = assigned.map { |zone| zone.assignment["dwelling_id"] }.compact.uniq
        {
          "building_segment_id" => segment_id,
          "programs" => assigned.filter_map do |zone|
            zone.assignment["program_id"] && { "zone_id" => zone.id, "program_id" => zone.assignment["program_id"] }
          end,
          "dwelling_ids" => dwellings,
          "equipment_set_ids" => (assigned.map { |zone| zone.assignment["equipment_set_id"] } +
                                  dwellings.map { |id| state.dwelling(id)&.fetch("equipment_set_id") }).compact.uniq,
          "bedrooms" => sum(zones, "bedrooms"), "occupants" => sum(zones, "occupants")
        }
      end

      def sum(zones, key)
        values = zones.map { |zone| zone.assignment[key] }.compact
        values.empty? ? nil : values.sum
      end
    end
  end
end
