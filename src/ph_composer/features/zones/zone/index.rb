# frozen_string_literal: true

module PhComposer
  module Zones
    # One walk of a Model, reused for the length of one read phase.
    #
    # Resolution is the same shape every time: find the Zone occurrence a reference names, find the
    # Face inside it, and check whether that Face's id is duplicated anywhere in the Model. Each of
    # those asks `Occurrences` to walk the Model, so a gesture over N Faces walked it about 2N times.
    # Measured on SketchUp 26.1.188, that is O(targets x Model Faces): a 50-target gesture cost 459 ms
    # in a 252-Face Model and 3,352 ms in a 2,004-Face one, and the Face read had the same defect
    # through `Adjacency.state`. With the index, the 50-target gesture costs 164 ms at 2,004 Faces.
    #
    # An index walks once and answers from what it found. Every walk is lazy, so a caller that
    # passes one pays for exactly the walks it would have paid for anyway, and no more.
    #
    # **It is only valid while the Model does not change.** It holds occurrence paths, transforms
    # and the records read at walk time. What qualifies is a phase with no write in it before its
    # last resolve: a query, the part of an action that resolves targets before proposing anything,
    # and `ClassifyStep`, which resolves and checks every target before it writes the first one.
    # What does not qualify is a step that mutates and then has to see what it did, which is why
    # the adjacency cut and every other geometry step keeps walking the live Model.
    class Index
      attr_reader :model

      def initialize(model)
        @model = model
      end

      # An index answers for the Model it walked and no other. Reads take a Model and an optional
      # index, and one open Model's index handed to another's read would answer about the wrong
      # document while the write landed on this one. Nothing does that today; this is what stops it
      # being silent if something ever does.
      def check!(model)
        return self if model.equal?(@model)

        raise InternalError, "This occurrence index was built for another Model."
      end

      def zones
        @zones ||= Occurrences.scan_zones(@model)
      end

      # The Faces of one Zone occurrence, walked once per Zone however often they are asked for.
      def faces(zone)
        @faces_by_path ||= {}
        @faces_by_path[zone.path] ||= Occurrences.scan_faces(zone)
      end

      def all_faces
        @all_faces ||= zones.flat_map { |zone| faces(zone) }
      end

      # Every Face occurrence carrying each Face record id, so the ambiguity check inside
      # `resolve_face` is a hash lookup rather than a walk of every Zone.
      def faces_by_id
        @faces_by_id ||= all_faces.group_by { |face| Occurrences.face_record(face.entity)&.fetch("id", nil) }
                                  .reject { |id, _faces| id.nil? }
      end

      def faces_with_id(id)
        faces_by_id.fetch(id, [])
      end
    end

    # The children of each Entities collection by persistent id, for one read over many explicit paths.
    #
    # Resolving a path finds each step by scanning its collection, so a read of N paths into one Zone
    # scanned that Zone's entities about 2N times. Measured on SketchUp 26.1.188, 5,000 Edge paths in Zones
    # of 5,000 Edges cost 10 s in `containment` and 12 s in `faces.host_context`. A lookup scans
    # each collection a read steps into once, the first time, and answers every later step from that.
    #
    # It is valid for one read only, as an Index is: it holds what each collection held when first asked.
    # SketchUp keeps one Ruby object per collection, so collections are told apart by identity.
    class ChildLookup
      def initialize
        @by_collection = {}.compare_by_identity
      end

      def matching(entities, persistent_id)
        (@by_collection[entities] ||= entities.to_a.group_by(&:persistent_id)).fetch(persistent_id, [])
      end
    end
  end
end
