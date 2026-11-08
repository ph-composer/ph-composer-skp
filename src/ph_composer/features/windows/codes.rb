# frozen_string_literal: true

module PhComposer
  module Windows
    # The codes Windows raises, published in docs/API_REFERENCE.md: `window_type.*` for a Window Type's
    # conditions and `window.*` for a placed Window Unit's. A Unit read, an action's refusal and the
    # export preflight use the same code for the same condition.
    module Codes
      ALL = {
        "window.copy_id_pending" => "A native copy shares this Window's identity until it is repaired.",
        "window.definition_changed" => "The Window's geometry differs from its Type; reset it first.",
        "window.definition_detached" => "The Window does not use its Type's primary definition.",
        "window.definition_editing" => "The Window definition is open for editing; close it first.",
        "window.definition_missing" => "The Type's primary definition no longer matches the Type.",
        "window.edited_geometry_replaced" => "The Type edit replaces edited primary Window geometry.",
        "window.geometry_differs" => "The Window's generated geometry or cutting behaviour differs from its Type.",
        "window.host_boundary_unsupported" => "The host Face's boundary condition is not Outdoors.",
        "window.host_required" => "The action needs the matching host Face for this Window.",
        "window.host_type_unsupported" => "The host Face is neither a Wall nor a Roof/Ceiling.",
        "window.host_unclassified" => "The host Face has no Face type or owning Zone.",
        "window.host_zone_unresolved" => "The host Face is not in one unambiguous authored Zone.",
        "window.mirrored" => "The Window is mirrored; make a new flipped Type.",
        "window.nested_units" => "A Window is nested inside another Window.",
        "window.not_component" => "A Window record is not on a native ComponentInstance.",
        "window.not_mirrored" => "The chosen Window is not mirrored.",
        "window.off_host" => "The Window does not lie in its host Face's plane.",
        "window.opening_area_exceeds_host" => "The Windows on a Face cover more than its gross area.",
        "window.outlines_required" => "The action needs every Window outline keyed by occurrence path.",
        "window.overhang" => "The Window extends past its host Face or into one of its holes.",
        "window.no_host_face" => "No Face of a Zone beside the Window has room for it.",
        "window.overlap" => "The Window overlaps another Window on the same host.",
        "window.rehost_parent" => "A re-host Face must be in the Window's existing parent storage.",
        "window.restore_unavailable" => "The stamped panes do not uniquely match the Type's outline.",
        "window.scaled" => "The Window has native in-plane scaling.",
        "window.shared_definition_reset" => "Reset replaces an edited primary definition for all of its Windows.",
        "window.sheared" => "The Window has native in-plane shear.",
        "window.surface_host" => "A paired Surface Face cannot host a Window.",
        "window.type_geometry_unknown" => "A neighbouring Window's untouched geometry cannot be recovered.",
        "window.unhosted" => "The Window is not glued to a resolvable host Face.",
        "window.unknown_type" => "The Window names a Window Type that is not in the Model.",
        "window_type.construction_unavailable" => "An element's Uw is outside what the pinned Honeybee simple " \
                                                  "glazing material accepts.",
        "window_type.construction_unresolved" => "An element is missing a Glazing Ug, Frame Uf or Frame psi-g value.",
        "window_type.default_install_dangling" => "The Model default Psi-Install Type is not in the Model.",
        "window_type.dimensions_incomplete" => "A row or column dimension is missing or not positive.",
        "window_type.frame_operation_mismatch" => "A Frame's operation differs from its element's operation.",
        "window_type.frame_width_unresolved" => "An element's Frame width is missing.",
        "window_type.g_value_missing" => "An element's Glazing has no g-value.",
        "window_type.geometry_unavailable" => "The Type's opening area cannot be calculated.",
        "window_type.glazing_area_nonpositive" => "An element's Frame widths leave no glazing area.",
        "window_type.install_unresolved" => "No Psi-Install Type resolves for an element side.",
        "window_type.no_glazed_elements" => "Every element of the Type is empty.",
        "window_type.operation_incomplete" => "An element has no operation or no opening direction.",
        "window_type.partial_shared_edge" => "An element edge is only partly shared, which has no proved " \
                                             "installation mapping.",
        "window_type.product_dangling" => "An element names a Frame, Glazing or Psi-Install Type that is not in the " \
                                          "Model."
      }.freeze

      module_function

      def install(feature)
        ALL.each { |code, description| feature.code(code, :description => description) }
      end
    end
  end
end
