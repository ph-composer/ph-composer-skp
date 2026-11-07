# frozen_string_literal: true

module PhComposer
  module Spaces
    # Whether a Face may become a Floor Segment or the floor of a new Volume, as one rule the candidate
    # read and the two actions share: a read that calls a Face eligible is accepted by the action at the
    # same revision, and one it refuses meets the same code there.
    module Eligibility
      MARK = "#{FEATURE_ID}.floors.mark"
      CREATE_VOLUME = "#{FEATURE_ID}.volumes.create"
      WALL = "The Face is vertical, a wall. A Space is a floor outline plus a height: select only the floor."

      module_function

      # Raises the refusal `floors.mark` gives a Face directly inside `volume`.
      def floor!(scan, volume)
        unless scan.volumes.any? { |candidate| candidate.equal?(volume) }
          raise CodedError.new("target.wrong_hierarchy", "Mark floor takes Faces directly inside a Volume that " \
                                                         "is in a Space.")
        end

        Resolve.writable!(volume, scan.volumes + scan.orphan_volumes, "Volume")
      end

      # Raises the refusal `volumes.create` gives a Face loose at `space`'s root.
      def new_volume!(scan, space)
        Resolve.writable!(space, scan.spaces, "Space")
      end

      # Raises the refusal `volumes.create` gives this Face named alone: one that shares an Edge with
      # another Face would carry it away. Named together with every Face it touches, it may be accepted.
      def alone!(face)
        return if Steps.sharing([face.entity], [face.entity.persistent_id]).empty?

        raise CodedError.new("space.shares_edge", "The Face shares an Edge with another Face; name it together " \
                                                  "with the Faces it touches to make one Volume of them.")
      end

      # Whether `face`, whose vertices `transform` maps to world, stands vertical: a wall, never a floor.
      def wall?(face, transform)
        normal = face.normal
        Metrics.vertical?(FaceGeometry.world_normal([normal.x, normal.y, normal.z], transform.to_a))
      end

      # Raises the refusal both actions give a wall: it has no plan area, so it cannot be a Floor Segment.
      def not_a_wall!(face, transform)
        raise CodedError.new("target.wrong_kind", WALL) if wall?(face, transform)
      end

      # The operation a candidate Face is for and the refusal it would meet now, named alone, or nil for none.
      def of(scan, face)
        operation = face.volume ? MARK : CREATE_VOLUME
        face.volume ? floor!(scan, face.volume) : new_volume!(scan, face.space)
        not_a_wall!(face.entity, face.transform)
        alone!(face) unless face.volume
        [operation, nil]
      rescue CodedError => error
        [operation, { "code" => error.code, "message" => error.message }]
      end
    end
  end
end
