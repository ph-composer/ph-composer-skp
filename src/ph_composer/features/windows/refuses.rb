# frozen_string_literal: true

module PhComposer
  module Windows
    # The codes Windows operations refuse with, beyond the common sets of their kind (context/CONTRACTS.md,
    # "Outcomes and codes"). Every write first walks the Window Units and repairs copied identities
    # (Units::Mutation.prepare), so every action answers WRITE; a Type edit then updates every Unit of the
    # Type on its host Face.
    module Refuses
      PAGE = %w[query.cursor_expired query.limit_invalid].freeze
      # Reading placed Window Units walks their host Zones and Faces.
      UNIT_READ = %w[geometry.invalid record.unreadable target.wrong_kind validation.failed].freeze
      WRITE = %w[copy.rule_missing extension.invalid identity.conflict record.unreadable reference.invalid
                 target.ambiguous target.locked target.shared_definition target.wrong_kind validation.failed].freeze
      EDIT = (WRITE + %w[target.changed target.not_found]).freeze
      DUPLICATE = (WRITE + %w[target.not_found]).freeze
      DELETE = (EDIT + %w[reference.in_use]).freeze
      # Placing or reshaping a Unit on its host Face.
      UNIT_GEOMETRY = (EDIT + %w[geometry.invalid target.wrong_hierarchy target.wrong_zone window.overhang
                                 window.overlap window.surface_host window.type_geometry_unknown]).freeze
      TYPE_EDIT = (UNIT_GEOMETRY + %w[window.definition_editing window.definition_missing window.host_required
                                      window.nested_units]).freeze
      TYPE_DELETE = (TYPE_EDIT + %w[reference.in_use window.definition_changed window.unknown_type]).freeze
      SWAP_TYPE = (TYPE_EDIT + %w[window.definition_changed window.unknown_type]).freeze
      NEW_FLIPPED_TYPE = (TYPE_EDIT - %w[window.nested_units] +
                          %w[window.definition_changed window.not_mirrored]).freeze
      RESET_TO_TYPE = (TYPE_EDIT - %w[target.wrong_hierarchy target.wrong_zone] +
                       %w[window.mirrored window.unknown_type]).freeze
      RESTORE = (UNIT_GEOMETRY + %w[window.definition_changed window.definition_missing
                                    window.restore_unavailable]).freeze
      RETURN_TO_HOST = %w[geometry.invalid record.unreadable target.ambiguous target.changed target.locked
                          target.not_found target.shared_definition target.wrong_hierarchy target.wrong_kind
                          target.wrong_zone validation.failed window.definition_changed window.mirrored
                          window.no_host_face window.scaled window.sheared window.surface_host
                          window.type_geometry_unknown window.unknown_type].freeze
      # Choosing a host Face for the Place tool resolves it as a Zones Face occurrence.
      PLACE_TOOL_CHOOSE = %w[record.unreadable target.ambiguous target.changed target.locked target.not_found
                             target.shared_definition target.wrong_hierarchy target.wrong_kind target.wrong_zone
                             validation.failed window.surface_host].freeze
      # Reading a host Face's placement extent locates it as a placement would.
      HOST_EXTENT = (PLACE_TOOL_CHOOSE + %w[geometry.invalid]).freeze
      # Copying library rows into the Model through the library's copy participant.
      # The library copy participant's own codes reach the Installs save through its `participants`
      # edge; this is the one a staged import raises itself.
      LIBRARY_COPY = %w[library.local_choice_required].freeze
    end
  end
end
