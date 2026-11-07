# frozen_string_literal: true

module PhComposer
  module Zones
    # The codes Zones raises under its own nouns, published in docs/API_REFERENCE.md. Shared-noun
    # codes (target.*, geometry.*) are listed in context/CONTRACTS.md.
    module Codes
      ALL = {
        "adjacency.counterpart_omitted" => "A Surface Face's counterpart is omitted from the export, so the pair " \
                                           "is exported as omitted too.",
        "adjacency.glued_instances" => "A Face carries glued Component instances and was not cut for adjacency.",
        "adjacency.invalid" => "A Face's stored Surface adjacency cannot be read.",
        "adjacency.multiple_neighbours" => "A Face meets more than one neighbouring Zone and was not cut.",
        "adjacency.not_surface" => "The Face has no Surface pair to retire.",
        "adjacency.overlapping_zones" => "Two Zones overlap, facing the same way, so no Surface pair was made.",
        "adjacency.sliver_skipped" => "A shared region below the geometry tolerance was not cut.",
        "adjacency.stale" => "A Surface pair's geometry changed since it was matched; the Face is omitted.",
        "adjacency.unresolved" => "A Surface pair's counterpart cannot be found or does not point back.",
        "adjacency.unsupported_shape" => "A shared region's shape cannot be cut exactly.",
        "assignment.pending" => "An Attached zone assignment is still open; finish it first.",
        "attached_zone.absent" => "An AttachedZone Face names no Attached zone.",
        "attached_zone.dangling" => "An AttachedZone Face names an Attached zone that is not in the Model.",
        "attached_zone.factor_below_phius_floor" => "An Attached zone's factor is below the Phius floor and needs " \
                                                    "the Phius Temperature Reduction Factor evidence.",
        "attached_zone.invalid" => "An AttachedZone Face names an Attached zone record that cannot be read.",
        "attached_zone.unavailable" => "An AttachedZone Face names an Attached zone written by a newer schema or " \
                                       "carrying extension data this installation does not understand.",
        "construction.dangling" => "A Face names an Assembly that is not in the Model.",
        "construction.incomplete" => "A Face names an Assembly that cannot export yet; the message gives the first " \
                                     "of its export_blockers.",
        "construction.invalid" => "A Face names an Assembly record that cannot be read.",
        "construction.missing" => "An exported Face names no Assembly. An interior Face within one " \
                                  "Building-Segment needs none.",
        "face.assembly_exterior_condition_mismatch" => "The Face's boundary condition differs from its Assembly's " \
                                                       "exterior condition.",
        "face.assembly_pair_mismatch" => "The two Faces of a Surface pair do not hold one Assembly, " \
                                         "reversed on one side.",
        "face.assembly_type_mismatch" => "The Face's type differs from its Assembly's type.",
        "face.boundary_unassigned" => "A Face has no boundary condition and is omitted from the export.",
        "face.identity_unique" => "The Face has no split copies sharing its identity to repair.",
        "face.invalid" => "A Face's assignment record cannot be read.",
        "face.type_missing" => "A Face has no Face type.",
        "face.unclassified" => "A Zone has unclassified Faces.",
        "face.wrong_zone" => "A Face is contained by more than one Zone.",
        "gesture.retirement_conflict" => "One gesture would retire the same Face's pair two different ways.",
        "gesture.too_large" => "The gesture selects more Faces than one edit may change.",
        "zone.option_duplicate" => "An equivalent managed option name already exists.",
        "zone.option_export_conflict" => "Distinct Building Segments share one export identifier; map to a survivor.",
        "zone.options_conflict" => "Recovery or shared-storage choice evidence conflicts; explicit repair is required.",
        "zone.options_adoption_required" => "Adopt the legacy or copied choices before editing categories.",
        "zone.component" => "A Zone record sits on a component, as Make Component leaves it, so it is not read " \
                            "as a Zone; Undo, or explode the component and restore the Zone.",
        "zone.identity_in_use" => "The Zone being restored is already in the Model.",
        "zone.identity_unique" => "The Zone's identity is already unique; there is nothing to repair.",
        "zone.none" => "The Model has no Zone to export.",
        "zone.restore_is_limited" => "Restore recovers the Zone id, Building-Segment and Level only.",
        "zone.restore_unsafe" => "The Zone cannot be restored from what remains."
      }.freeze

      module_function

      def install(feature)
        ALL.each { |code, description| feature.code(code, :description => description) }
      end
    end
  end
end
