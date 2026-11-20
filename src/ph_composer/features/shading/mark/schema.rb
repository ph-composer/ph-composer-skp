# frozen_string_literal: true

module PhComposer
  module Shading
    FEATURE_ID = "ph_composer.shading"

    # The shading mark: one record, `{"schema_version": 1}`, on a Face, a Group or a ComponentInstance, with no
    # durable id. It claims nothing, so Make Zone stays open around it, and its store excludes from the
    # envelope, so a Zone can leave out a Face it reaches (context/CONTRACTS.md, "The shading mark"). Every read
    # goes by presence: a mark whose text cannot be parsed still marks its entity, and clear still removes it.
    module Mark
      STORE = Records::EntityStore.new(FEATURE_ID, :excludes_from_envelope => true)
      RECORD = { "schema_version" => 1 }.freeze
      # One assign or clear names at most this many entities; one more refuses the whole command.
      TARGET_LIMIT = 250
      # The entity kinds the mark sits on, as a reference row names them.
      KINDS = %w[face group component_instance].freeze

      module_function

      def marked?(entity)
        STORE.marks?(entity)
      end

      # Whether the stored text is a JSON object, which is all a mark has to be: a read never refuses it.
      def readable?(entity)
        entity.get_attribute(STORE.dictionary, STORE.key).is_a?(String) && STORE.read(entity).is_a?(Hash)
      rescue CodedError => error
        raise unless error.code == "record.unreadable"

        false
      end

      # The kind a reference row names, or nil for an entity the mark never sits on.
      def kind(entity)
        if entity.is_a?(Sketchup::Face) then "face"
        elsif entity.is_a?(Sketchup::Group) then "group"
        elsif entity.is_a?(Sketchup::ComponentInstance) then "component_instance"
        end
      end

      def write(entity)
        STORE.write(entity, RECORD)
      end

      def delete(entity)
        STORE.delete(entity)
      end

      def check_limit!(count)
        return if count <= TARGET_LIMIT

        raise CodedError.new("gesture.too_large", "One command names at most #{TARGET_LIMIT} entities; this one " \
                                                  "names #{count}. Nothing was written.")
      end
    end
  end
end
