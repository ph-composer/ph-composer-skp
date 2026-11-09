# frozen_string_literal: true

require "digest"

module PhComposer
  module ColourBy
    # The colours the shared service owns: the two states every mode has, and the two helpers a mode
    # builds its colour function from. A mode's own hues belong to the feature that declares it, so
    # nothing here names a face type, a boundary condition or a Zone.
    module Palette
      # A value the mode does not colour: the entity carries a record but not enough of one to paint.
      INCOMPLETE = [255, 176, 0].freeze
      # No record at all. Drawn as a hatch and solid boundary rather than a fill.
      UNCLASSIFIED = [130, 130, 130].freeze
      # The lines a readout draws, one colour whichever readout draws them.
      READOUT_LINE = [38, 96, 150].freeze
      FILL_ALPHA = 110
      OUTLINE_ALPHA = 220

      # A categorical ramp for modes whose values are open, such as Zone names. Picking by a stable
      # digest of the value keeps a Zone the same colour as Zones around it come and go.
      RAMP = [
        [31, 119, 180], [255, 127, 14], [44, 160, 44], [214, 39, 40], [148, 103, 189],
        [140, 86, 75], [227, 119, 194], [127, 127, 127], [188, 189, 34], [23, 190, 207]
      ].freeze

      module_function

      # A colour function over a fixed table: the mode's own hues, nil for anything else.
      def fixed(table)
        frozen = table.freeze
        ->(value) { frozen[value] }
      end

      # A colour function over the categorical ramp, stable for a given value. Values are coloured one at a
      # time, so two can share a hue; a projection that sees every value uses `spread` instead.
      def ramp
        ->(value) { value.nil? ? nil : RAMP[value.to_s.sum % RAMP.length] }
      end

      # A ramp colour for each of `values`, distinct up to the ramp's length, for an entry's own `colour`.
      # Each value prefers a slot its digest picks; when two prefer one slot, the later in sorted order
      # takes the next free one. A value usually keeps its colour as others come and go; one that arrives
      # or leaves can move a value it clashes with, directly or along a run of occupied slots.
      # `reserved` are colours already on screen in the same pass (a managed option's own); their ramp slots
      # are taken first, so no spread value repeats one.
      def spread(values, reserved: [])
        taken = reserved.filter_map { |colour| RAMP.index(colour) }.to_h { |index| [index, true] }
        values.compact.uniq.sort_by(&:to_s).each_with_object({}) do |value, colours|
          index = slot(value)
          index = (index + 1) % RAMP.length while taken.key?(index) && taken.length < RAMP.length
          taken[index] = true
          colours[value] = RAMP[index]
        end.freeze
      end

      # `entries` with each one that has a value but no colour of its own given its `spread` colour, so a
      # ramp mode's values are told apart up to the ramp's length. An entry whose record names its colour
      # (a managed option) keeps it, and its ramp slot is not given to another. Answers `entries`.
      def spread_entries(entries)
        open = entries.select { |entry| entry.colour.nil? && !entry.value.nil? }
        colours = spread(open.map(&:value), :reserved => entries.filter_map(&:colour).uniq)
        open.each { |entry| entry.colour = colours.fetch(entry.value) }
        entries
      end

      # A digest, not `ramp`'s byte sum: ids differing only in order share a byte sum, and fewer clashes
      # means fewer values moved as others come and go.
      def slot(value)
        Digest::SHA256.digest(value.to_s).unpack1("N") % RAMP.length
      end
      private_class_method :slot
    end
  end
end
