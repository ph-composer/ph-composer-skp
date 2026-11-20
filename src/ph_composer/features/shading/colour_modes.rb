# frozen_string_literal: true

module PhComposer
  module Shading
    # The Shading Colour-by mode (context/EXTENSIBILITY.md, "Colour-by modes"): one entry per Shading Face
    # occurrence, keyed by the component name it exports under, each name its own colour. An unmarked Face has
    # no entry, so it keeps SketchUp's own colour. Each entry carries its root path and world transform, so a
    # placement is told from the others and hidden tags hide its drawing. The legend sums each row's world area
    # through the entry figure, shown in the display units. The projection reads what `shading.list`
    # reads, Zones' occurrences and then one walk of the Model, by the same rule (Inventory.shading_face?).
    # A Face whose transform is singular has no area to give; it is amber with no figure, so one bad placement
    # does not turn the mode off, and `shading.list` names it as geometry.invalid.
    module ColourModes
      BY_COMPONENT = "#{FEATURE_ID}.by_component"

      module_function

      def install(feature)
        feature.colour_mode(BY_COMPONENT, :label => "Shading", :entity_kind => "face",
                                          :colours => ColourBy::Palette.ramp) { |read| entries(read.model) }
      end

      def entries(model)
        built = []
        Inventory.shading_faces(model) do |face, path, transform, name|
          area = area_m2(face, transform)
          built << ColourBy::Entry.new(:entity => face, :transform => transform, :path => path, :value => name,
                                       :label => name, :state => area ? nil : :incomplete,
                                       :figure => area && ["area", area])
        end
        ColourBy::Palette.spread_entries(built)
      end

      # The occurrence's world area in m2, or nil when the transform flattens the Face.
      def area_m2(face, transform)
        FaceCapture.call(face, transform).area_m2
      rescue CodedError => error
        raise unless error.code == "geometry.invalid"

        nil
      end
    end
  end
end
