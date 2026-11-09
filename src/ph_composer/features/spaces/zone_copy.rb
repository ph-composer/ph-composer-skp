# frozen_string_literal: true

module PhComposer
  module Spaces
    # Spaces' part of a Zone occurrence becoming independent (`ph_composer.zones.occurrence_independent`;
    # context/CONTRACTS.md, "Compound proposals"). Every Space, Volume and Floor Segment inside the
    # occurrence whose id another occurrence holds takes a new id, and each renamed Volume a new Space
    # Floor, in the Zone's own proposal, so the copy and its Spaces are independent in one Undo step.
    # Numbers and values are kept. Payloads and a copied Space's `zone_id` are remapped to the Zone's new
    # ids (the collection-copy contract, context/CONTRACTS.md, "Space membership"): a Space outside the
    # Zone under the same added container (`copy_added`) follows it to the new id, and one whose Zone
    # stayed behind keeps its reference. The Zone stamps on the Space Groups are Zones' to rewrite. The
    # steps bind logically and add only restorable writes, because the Zone copy watcher's follow-up cannot
    # abort.
    module ZoneCopy
      NAME = "#{FEATURE_ID}.follow_zone_copy"
      TRANSITION = "ph_composer.zones.occurrence_independent"
      REFUSES = %w[copy.rule_missing extension.invalid identity.conflict reference.invalid target.changed
                   target.locked target.shared_definition validation.failed].freeze

      module_function

      def install(feature)
        feature.transition_contributor(NAME, :transition => TRANSITION, :refuses => REFUSES) do |*args|
          contribute(*args)
        end
      end

      def contribute(request, proposal, description)
        zone_path = description.fetch("zone_path")
        allocate = Records::Identity.allocator(request, "transition" => TRANSITION,
                                                        "zone_id" => description.fetch("new_zone_id"))
        parent = { :mapping => description.fetch("mapping"),
                   :references => description.fetch("references").map do |row|
                     Records::ReferenceEntry.new(:kind => row.fetch("kind"), :key => row.fetch("key"),
                                                 :record => row.fetch("record"))
                   end }
        # Records outside the copied Zone only say which ids are held there; one that does not read is
        # not this repair's to refuse.
        scan = Occurrences.scan(request.model, :strict => zone_path)
        plan = IdentityPlan.build(scan, nil, :number => nil, :allocate => allocate,
                                             :catalog => request.registry.catalog, :engine => request.engine,
                                             :scope => zone_path, :parent => parent)
        planned = plan.rows.empty? ? [] : identity_step(proposal, plan, zone_path)
        planned + follow_in_copy(proposal, scan, description, request.model)
      end

      def identity_step(proposal, plan, zone_path)
        step = IdentityStep.new(:plan => plan, :scope_path => zone_path)
        proposal.add_step(step, :scopes => [])
        step.planned
      end

      # Each Space carried by the same added container as the Zone, and outside every Zone, whose record
      # names it. An array copy adds one container per copy: a Space follows only the Zone in its own. A
      # Space inside any Zone is that Zone's to rewrite; one below shared storage, such as a component, or
      # locked stays as copied with its finding. The Space's own definition may still be shared: its record
      # is on its own instance.
      def follow_in_copy(proposal, scan, description, model)
        root = (description.fetch("zone_path") & description.fetch("copy_added")).first
        return [] unless root

        zones = Zones::Occurrences.zones(model).map(&:path)
        scan.spaces.select do |space|
          (space.path & description.fetch("copy_added")).first == root && !space.shared_above && !space.locked &&
            space.record["zone_id"] == description.fetch("old_zone_id") &&
            zones.none? { |path| path.length < space.path.length && space.path[0, path.length] == path }
        end.map do |space|
          after = space.record.merge("zone_id" => description.fetch("new_zone_id"))
          Spaces.validate!(SPACE, after)
          proposal.add_step(ZoneReferenceStep.new(:path => space.path, :before => space.record, :after => after),
                            :scopes => [])
          { "kind" => SPACE_KIND, "id" => after.fetch("id"), "change" => "updated" }
        end
      end
    end
  end
end
