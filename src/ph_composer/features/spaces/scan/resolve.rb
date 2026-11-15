# frozen_string_literal: true

module PhComposer
  module Spaces
    # Strict resolution of an explicit Space, Volume or Floor Segment reference. Paths locate
    # candidates; the record id proves identity. Nothing searches by name or geometry to repair a
    # stale reference.
    module Resolve
      # One kind's reference: the id key it carries, the label refusals use, and every occurrence of the
      # kind a scan holds, strays included.
      Target = Struct.new(:id_key, :label, :occurrences, keyword_init: true) do
        def occurrences_in(scan)
          occurrences.call(scan)
        end
      end

      TARGETS = {
        SPACE_KIND => Target.new(:id_key => "space_id", :label => "Space", :occurrences => ->(scan) { scan.spaces }),
        VOLUME_KIND => Target.new(:id_key => "volume_id", :label => "Volume",
                                  :occurrences => ->(scan) { scan.volumes + scan.orphan_volumes }),
        FLOOR_SEGMENT_KIND => Target.new(:id_key => "floor_segment_id", :label => "Floor Segment",
                                         :occurrences => ->(scan) { scan.segments + scan.misplaced_segments })
      }.freeze

      module_function

      # The reference's kind, read from which id key it carries.
      def kind_of(reference)
        kinds = TARGETS.select { |_kind, target| reference.key?(target.id_key) }.keys
        return kinds.first if kinds.length == 1

        raise CodedError.new("params.invalid", "A reference names one Space, Volume or Floor Segment id.")
      end

      # A write refuses a copied identity, shared storage and a lock, each with nothing written.
      def occurrence(scan, reference, mutable:)
        kind = kind_of(reference)
        target = TARGETS.fetch(kind)
        path = integer_path(reference.fetch("entity_path"))
        candidates = target.occurrences_in(scan)
        found = candidates.find { |occurrence| occurrence.path == path }
        raise CodedError.new("target.not_found", "That #{target.label} occurrence no longer exists.") unless found
        unless found.record.fetch("id") == reference.fetch(target.id_key)
          raise CodedError.new("target.changed", "The #{target.label} identity has changed.")
        end

        writable!(found, candidates, target.label) if mutable
        found
      end

      # A Space Floor has no record of its own: its reference names its Volume's `floor_id` and the Volume's
      # path, and resolves to the Volume, under the Volume's write refusals. It names no other id.
      def floor(scan, reference, mutable:)
        if TARGETS.each_value.any? { |target| reference.key?(target.id_key) }
          raise CodedError.new("params.invalid", "A Space Floor reference names its floor_id and its Volume's " \
                                                 "entity_path only.")
        end

        candidates = TARGETS.fetch(VOLUME_KIND).occurrences_in(scan)
        path = integer_path(reference.fetch("entity_path"))
        found = candidates.find { |occurrence| occurrence.path == path }
        raise CodedError.new("target.not_found", "That Space Floor's Volume no longer exists.") unless found
        unless found.record.fetch("floor_id") == reference.fetch("floor_id")
          raise CodedError.new("target.changed", "The Space Floor identity has changed.")
        end

        writable!(found, candidates, "Space Floor") if mutable
        found
      end

      def writable!(found, candidates, label)
        if candidates.count { |occurrence| occurrence.record.fetch("id") == found.record.fetch("id") } > 1
          raise CodedError.new("target.ambiguous",
                               "That #{label} shares its identity with a copy. Nothing was written.")
        end
        if found.shared
          raise CodedError.new("target.shared_definition",
                               "That #{label} is inside shared component storage. Nothing was written.")
        end
        return unless found.locked

        raise CodedError.new("target.locked", "That #{label} or a Group above it is locked. Nothing was written.")
      end

      def integer_path(value)
        Array(value).map { |id| Integer(id) }
      rescue ArgumentError, TypeError
        raise CodedError.new("params.invalid", "Occurrence paths contain only persistent-id integers.")
      end
    end
  end
end
