# frozen_string_literal: true

module PhComposer
  module Zones
    module Faces
      # This feature's Colour-by modes: face type, boundary condition and assigned Assembly.
      #
      # The hues are honeybee's own defaults, so a modeler sees the same colours in SketchUp, Rhino
      # and honeybee-display (`honeybee-core/honeybee/face.py` and `boundarycondition.py`). Stored
      # values keep honeybee's names; the legend shows the glossary's words.
      module ColourModes
        BY_ASSEMBLY = "#{PREFIX}.by_assembly"
        BY_FACE_TYPE = "#{PREFIX}.by_face_type"
        BY_BOUNDARY_CONDITION = "#{PREFIX}.by_boundary_condition"

        PAINT_MODES = { "face_type" => BY_FACE_TYPE, "boundary_condition" => BY_BOUNDARY_CONDITION,
                        "attached_zone_id" => BY_BOUNDARY_CONDITION, "assembly_id" => BY_ASSEMBLY }.freeze

        FACE_TYPE_COLOURS = {
          "Wall" => [230, 180, 60], "RoofCeiling" => [128, 20, 20], "Floor" => [128, 128, 128],
          "AirBoundary" => [255, 255, 200]
        }.freeze
        FACE_TYPE_LABELS = { "RoofCeiling" => "Roof or ceiling", "AirBoundary" => "Air boundary" }.freeze

        # Attached zone takes honeybee's Other until it is given a hue of its own.
        BOUNDARY_COLOURS = {
          "Outdoors" => [64, 180, 255], "Ground" => [165, 82, 0], "Adiabatic" => [255, 128, 128],
          "Surface" => [0, 128, 0], "AttachedZone" => [255, 255, 200]
        }.freeze
        BOUNDARY_LABELS = { "Adiabatic" => "To neighbour", "AttachedZone" => "Attached zone" }.freeze

        module_function

        # The view mode a concrete paint choice shows while the tool runs, across panel and native routes.
        def paint_mode(field)
          PAINT_MODES[field]
        end

        def install(feature)
          feature.colour_mode(BY_FACE_TYPE, :label => "Face type", :entity_kind => "face",
                                            :colours => ColourBy::Palette.fixed(FACE_TYPE_COLOURS)) do |read|
            entries(read.model, "face_type", FACE_TYPE_LABELS)
          end
          feature.colour_mode(BY_BOUNDARY_CONDITION, :label => "Boundary", :entity_kind => "face",
                                                     :colours => ColourBy::Palette.fixed(BOUNDARY_COLOURS)) do |read|
            entries(read.model, "boundary_condition", BOUNDARY_LABELS)
          end
          feature.colour_mode(BY_ASSEMBLY, :label => "Assembly", :entity_kind => "face", :group => "construction",
                                           :colours => method(:no_value_colour)) { |read| assembly_entries(read) }
        end

        # One dependency read per projection, never per Face. The value is the Assembly id, the legend's key;
        # each entry carries its Assembly's colour, read here, so the shared service needs no Model, feature
        # access or cached Index to colour it.
        def assembly_entries(read)
          rows = read.query("#{PREFIX}.assembly_choices").fetch("assemblies").to_h { |row| [row.fetch("id"), row] }
          Zones::Index.new(read.model).all_faces.map do |face|
            record = FACE_STORE.read(face.entity)
            id = record && record["assembly_id"]
            assembly = rows[id]
            ColourBy::Entry.new(:entity => face.entity, :transform => face.transform, :value => id,
                                :colour => assembly_colour(assembly && assembly.fetch("color")),
                                :label => assembly ? assembly.fetch("name") : id,
                                :state => id && !assembly ? :incomplete : nil, :path => face.zone.path + face.path,
                                :hatch_outline => false)
          end
        end

        # "#RRGGBB" as [r, g, b], or nil for an Assembly with no colour, which the service paints incomplete.
        def assembly_colour(color)
          color && color.delete_prefix("#").scan(/../).map { |component| component.to_i(16) }
        end

        # An Assembly's colour belongs to its record, so it comes on each entry; the id alone has none.
        def no_value_colour(_value)
          nil
        end

        # One entry per Face of every Zone, whether or not it carries a record. A Face with no record is
        # the legend's unclassified count, which is how a modeler finds what is left to classify.
        def entries(model, field, labels)
          Zones::Occurrences.zones(model).flat_map do |zone|
            Zones::Occurrences.faces(zone).map do |face|
              record = FACE_STORE.read(face.entity)
              value = record && record[field]
              ColourBy::Entry.new(:entity => face.entity, :transform => face.transform, :value => value,
                                  :label => value && labels.fetch(value, value), :state => state(record, value),
                                  :path => zone.path + face.path)
            end
          end
        end

        # A Face the legend cannot finish colouring, as against one it has nothing to colour.
        #
        # A record that carries no value for this mode's field is incomplete: the user classified the
        # Face, they just have not said this part yet. Calling it unclassified would put it in the same
        # count as a Face with no record at all, and send them to Suggest classification, which never
        # touches a Face that already has one. Only a Face with no record is unclassified, and the
        # service decides that from a nil value.
        #
        # An Attached zone with no chosen record is the same kind of half-filled state and blocks
        # canonical export, so it reads the same way.
        def state(record, value)
          return nil unless record
          return :incomplete if value.nil?

          value == "AttachedZone" && record["attached_zone_id"].nil? ? :incomplete : nil
        end
      end
    end
  end
end
