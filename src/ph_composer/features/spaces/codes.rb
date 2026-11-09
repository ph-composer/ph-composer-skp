# frozen_string_literal: true

module PhComposer
  module Spaces
    # The codes Spaces reports under its own noun, published in docs/API_REFERENCE.md.
    module Codes
      ALL = {
        "space.context_required" => "The edit context holding the Faces must be open to group them.",
        "space.duplicate_identity" => "Another occurrence carries this Space, Volume or Floor Segment's id: a copy.",
        "space.empty" => "A Space has no Volume.",
        "space.floor_projected" => "A Floor Segment is not horizontal; its plan area is used.",
        "space.height_missing" => "A Volume has no average clear ceiling height.",
        "space.identity_unique" => "The occurrence already has an identity of its own; there is nothing to repair.",
        "space.net_area_zero" => "A Volume has no net floor area, so no height can be derived from a solid.",
        "space.nested" => "A Space is inside another Space.",
        "space.offset_from_zone" => "A Space's Floor Segments lie outside its Zone's extents; it exports as drawn.",
        "space.nothing_to_create" => "None of the Faces given can become a Space.",
        "space.number_duplicate" => "Two Spaces in one Zone share a number.",
        "space.outside_zone" => "A Space is hosted in no Zone.",
        "space.zone_missing" => "A Space names a Zone that is no longer in the Model.",
        "space.same_zone" => "The Space is already in that Zone.",
        "space.solid_invalid" => "The chosen Group or component is not a closed solid, or encloses no volume.",
        "space.shares_edge" => "A Face shares an Edge with a Face outside the set being grouped.",
        "space.segment_misplaced" => "A Floor Segment record is on a Face that is not directly inside a Volume.",
        "space.position_unknown" => "The Volume has no stored position to restore.",
        "space.volume_moved" => "A Volume moved inside its Space since it was last left.",
        "space.volume_open" => "The Volume is open for editing; close it first.",
        "space.volume_protected" => "The Volume is protected; unprotect it before opening it.",
        "space.volume_unprotected" => "A closed Volume is unlocked, so its Faces can be edited from the Space.",
        "space.volume_empty" => "A Volume has no Floor Segment.",
        "space.volume_nested" => "A Volume is below another Group inside its Space rather than directly in it.",
        "space.volume_orphan" => "A Volume record is on a Group outside every Space."
      }.freeze

      module_function

      def install(feature)
        ALL.each { |code, description| feature.code(code, :description => description) }
      end
    end
  end
end
