# frozen_string_literal: true

module PhComposer
  module Spaces
    # Pure: the conditions a read row shows, as findings. Whether a code blocks export is this table's,
    # so a row and the export preflight cannot disagree about it.
    module Findings
      BLOCKS_EXPORT = {
        "space.outside_zone" => true, "space.zone_missing" => true, "space.empty" => false,
        "space.volume_empty" => false,
        "space.height_missing" => true, "space.number_duplicate" => false, "space.floor_projected" => false,
        "space.nested" => true, "space.volume_nested" => true, "space.volume_orphan" => true,
        "space.segment_misplaced" => true, "space.volume_moved" => false,
        "space.volume_unprotected" => false, "space.duplicate_identity" => true,
        "space.offset_from_zone" => false, "space.floor_overlap" => false, "space.floor_disconnected" => false
      }.freeze

      module_function

      # `repair` names the operation that clears it, when one does, so a reader offers it without parsing words.
      def finding(code, message, repair: nil)
        found = { "code" => code, "message" => message, "blocks_export" => BLOCKS_EXPORT.fetch(code) }
        repair ? found.merge("repair" => repair) : found
      end

      # `duplicate` says another Space in the same Zone carries this Space's number.
      def space(row, duplicate:)
        label = label(row)
        found = []
        found << unhosted(label, row.dig("values", "zone_id")) unless row["zone"]
        found << finding("space.nested", "#{label} is inside another Space.") if row["nested"]
        found << finding("space.empty", "#{label} has no Volume.") if row.fetch("volumes").empty?
        found << finding("space.number_duplicate",
                         "Another Space in this Zone is also number #{row.dig('values', 'number')}.") if duplicate
        found
      end

      # `zone_id` is the id the record still names, when it names a Zone that is gone.
      def unhosted(label, zone_id)
        return finding("space.outside_zone", "#{label} is in no Zone. Move it to a Zone.") unless zone_id

        finding("space.zone_missing", "#{label} is hosted in a Zone that is no longer in the Model. Move it to a " \
                                      "Zone, or remove it from the missing Zone.", :repair => "unhost")
      end

      # `floor_overlap` says two of its Floor Segments cover the same plan area; `floor_disconnected` that its Floor
      # Segments are not all joined by shared Edges.
      def volume(row, floor_overlap: false, floor_disconnected: false)
        name = "Volume #{row.dig('values', 'number')}"
        found = []
        found << finding("space.volume_nested", "#{name} is below another Group inside its Space.") if row["nested"]
        found << finding("space.volume_empty", "#{name} has no Floor Segment.") if row.fetch("floor_segments").empty?
        if floor_overlap
          found << finding("space.floor_overlap", "#{name} has Floor Segments that overlap in plan, so the area they " \
                                                  "share counts twice.")
        end
        if floor_disconnected
          found << finding("space.floor_disconnected", "#{name} has Floor Segments that share no Edge with the " \
                                                       "others, so its floor is in separate pieces.")
        end
        if !row["open"] && !row["protected"]
          found << finding("space.volume_unprotected", "#{name} is not protected; its Faces can be edited from the " \
                                                       "Space.")
        end
        if row["moved"]
          found << finding("space.volume_moved", "#{name} moved inside its Space. Restore its position.",
                           :repair => "restore_position")
        end
        unless row.dig("values", "avg_ceiling_height_m")
          found << finding("space.height_missing", "#{name} needs an average clear ceiling height.")
        end
        found
      end

      def segment(row)
        return [] if row.dig("metrics", "horizontal")

        [finding("space.floor_projected", "This Floor Segment is not horizontal; its plan area is used.")]
      end

      # Another occurrence carries this record's id: a copy. `repeated` says storage above its Space is
      # shared, a component or a copied Group, which no Spaces repair isolates. `ancestor` says the repair is
      # the named container's ("Space" or "Volume"): Make independent on it isolates this record with it.
      def duplicate(label, repeated:, ancestor: nil)
        message = if repeated
                    "This #{label} is repeated through shared storage, such as a component. Draw the Space " \
                      "directly; there is no repair."
                  elsif ancestor
                    "This #{label} shares its identity with a copy. Use Make independent on its #{ancestor}."
                  else
                    "This #{label} shares its identity with a copy. Use Make independent on the copy."
                  end
        finding("space.duplicate_identity", message, :repair => repeated || ancestor ? nil : "make_independent")
      end

      def orphan_volume
        finding("space.volume_orphan", "A Volume is outside any Space.")
      end

      def misplaced_segment
        finding("space.segment_misplaced", "A Floor Segment is not directly inside a Volume.")
      end

      def label(row)
        number = row.dig("values", "number").to_s
        name = row.dig("values", "name").to_s
        text = [number, name].reject(&:empty?).join(" ")
        text.empty? ? "A Space" : "Space #{text}"
      end
    end
  end
end
