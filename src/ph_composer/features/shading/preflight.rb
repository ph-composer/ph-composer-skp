# frozen_string_literal: true

module PhComposer
  module Shading
    # `shading.export_preflight`: what the mark leaves as it is, as non-blocking notes. A marked Group or
    # component that is a Zone or holds one, holds another feature's object, or holds a cutting component such
    # as a Window Unit, arises after assign refused it
    # (Make Zone inside a marked Group, a paste): the mark does not reach through the Zone or the object
    # (context/CONTRACTS.md, "The shading mark"), so its Faces stay what they are and this names the container.
    # Reads only.
    module Preflight
      SECTION = "#{FEATURE_ID}.export.shades"

      module_function

      def call(request)
        zones = Targets.zone_names(request.model)
        findings = []
        Inventory.walk(request.model.entities, [], [], Geom::Transformation.new,
                       zones) do |entity, path, _containers, _transform, cut|
          next if cut || entity.is_a?(Sketchup::Face) || !Mark.marked?(entity)

          what = held(entity, path, zones)
          findings << zone_inside(entity, path, what) if what
          reaches = !what && Targets.in_zone?(path, zones) && !Targets.cutting?(entity) && !Targets.owned?(entity)
          count = reaches ? Targets.classified_within(Targets.contents(entity).to_a) : 0
          findings << classified_inside(entity, path, count) if count.positive?
        end
        { "findings" => findings, "repairs" => [] }
      end

      # What the mark does not reach in a marked container, in words, or nil when it reaches everything.
      def held(entity, path, zones)
        contents = Targets.contents(entity).to_a
        return "a Zone" if zones.keys.any? { |zone_path| zone_path[0, path.length] == path }
        return "an object another feature owns, such as a Space" if Records::EntityStore.claimed_within?(contents)

        "a cutting component, such as a Window" if cutting_within?(contents)
      end

      def cutting_within?(entities)
        entities.any? do |entity|
          next false unless Targets.container?(entity)

          Targets.cutting?(entity) || cutting_within?(Targets.contents(entity).to_a)
        end
      end

      # A Face classified after the Group above it was marked stays envelope: classification wins.
      def classified_inside(entity, path, count)
        { "code" => "shading.classified_inside", "section" => SECTION, "object_id" => nil, "blocks_export" => false,
          "message" => "#{label(entity)} at path #{path.inspect} carries the shading mark and holds #{count} " \
                       "classified Zone Face(s). They stay part of the Zone's envelope and are not shading; clear " \
                       "their classification to make them shading." }
      end

      def label(entity)
        name = Targets.native_name(entity)
        Reads.named?(name) ? "\"#{name}\"" : "An unnamed Group or component"
      end

      def zone_inside(entity, path, what)
        { "code" => "shading.zone_inside", "section" => SECTION, "object_id" => nil, "blocks_export" => false,
          "message" => "#{label(entity)} at path #{path.inspect} carries the shading mark and is or holds #{what}. " \
                       "The mark does not reach it, so its Faces stay as they are and are not shading." }
      end
    end
  end
end
