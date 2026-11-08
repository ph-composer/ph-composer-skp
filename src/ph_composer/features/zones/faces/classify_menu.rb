# frozen_string_literal: true

module PhComposer
  module Zones
    module Faces
      # The native selection client sets one attribute per action, one list per attribute, and each
      # list marks the value every selected Face shares (none for a mixed selection). With no selection,
      # an Extensions menu choice loads the secondary paint tool through the same public view command as
      # the panel.
      module ClassifyMenu
        TYPE_MENU = "Set Face Type"
        BOUNDARY_MENU = "Set Face Boundary"
        ASSEMBLY_MENU = "Set Face Assembly"
        OFF = "Exit Classify tool"
        FIELDS = {
          "face_type" => { "values" => ASSIGNABLE_FACE_TYPES, "labels" => ColourModes::FACE_TYPE_LABELS,
                           "menu" => TYPE_MENU },
          "boundary_condition" => { "values" => ASSIGNABLE_BOUNDARIES - %w[AttachedZone],
                                    "labels" => ColourModes::BOUNDARY_LABELS, "menu" => BOUNDARY_MENU }
        }.freeze

        module_function

        def install(feature)
          classifiable = ->(read) { classifiable?(read.session) }
          FIELDS.each do |field, spec|
            spec.fetch("values").each { |value| declare(feature, field, value, spec, classifiable) }
          end
          feature.menu_entries("#{PREFIX}.assembly_menu", :menu => ASSEMBLY_MENU, :available => classifiable) do |read|
            Selection.client(read.session).assembly_entries
          end
          feature.menu_entries("#{PREFIX}.attached_choices", :menu => BOUNDARY_MENU,
                                                             :available => classifiable) do |read|
            Selection.client(read.session).attached_entries
          end
          feature.menu_item("#{PREFIX}.new_attached_zone_menu", :label => "New attached zone…", :menu => BOUNDARY_MENU,
                                                                :available => classifiable) do |session|
            Selection.client(session).open_assignment
          end
          tool_active = ->(read) { Faces.classify_tool(read.session).active? }
          feature.menu_entries("#{PREFIX}.classify_off", :menu => EXTENSION_NAME, :available => tool_active) do |_read|
            [Declarations::MenuEntry.new(:label => OFF, :handler => ->(session) { Faces.classify_tool(session).stop })]
          end
        end

        def declare(feature, field, value, spec, classifiable)
          label = spec.fetch("labels").fetch(value, value)
          state = ->(session) { Selection.client(session).check(field, value) }
          feature.menu_item("#{PREFIX}.classify_#{field}_#{value.downcase}",
                            :label => label, :menu => spec.fetch("menu"),
                            :available => classifiable, :state => state) do |session|
            Selection.client(session).classify(field, value)
          end
        end

        # Whether a right-click landed on something this palette paints, which is a Face and nothing
        # else. SketchUp selects what was right-clicked before it builds the menu, so the selection is
        # the signal.
        #
        # At the Model root a right-click on a Zone selects the Group, not a Face, so the palette is
        # not offered there: the Group is what the user pointed at, and Erase, Hide and Explode are
        # what they are likely to want. Opening the Zone and right-clicking a Face offers it.
        # Measured on 26.1.188, 2026-09-20.
        def classifiable?(session)
          Selection.available?(session)
        end
      end
    end
  end
end
