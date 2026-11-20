# frozen_string_literal: true

module PhComposer
  module Shading
    # The codes Shading reports under its own noun, published in docs/API_REFERENCE.md.
    module Codes
      ALL = {
        "shading.face_classified" => "A classified Zone Face cannot be shading until its classification is cleared " \
                                     "with ph_composer.zones.faces.clear_classification.",
        "shading.zone_target" => "The Group is a Zone or holds one; a whole Zone as shading is not supported.",
        "shading.inherited" => "Clear named an entity that is shading through a marked Group or component above " \
                               "it; the message names that one.",
        "shading.zone_inside" => "Preflight note: a marked Group or component is a Zone, holds one or holds " \
                                 "another feature's object or a cutting component, which the mark does not reach.",
        "shading.cutting_component" => "The entity is a cutting component or inside one; export does not read its " \
                                       "Faces."
      }.freeze

      module_function

      def install(feature)
        ALL.each { |code, description| feature.code(code, :description => description) }
      end
    end
  end
end
