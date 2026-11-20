# frozen_string_literal: true

module PhComposer
  module Shading
    # `shading.export_preflight`: what the mark leaves as it is, as non-blocking notes. A marked Group or
    # component that is a Zone or holds one, or holds another feature's object, arises after assign refused it
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

          holds_zone = zones.keys.any? { |zone_path| zone_path[0, path.length] == path }
          next unless holds_zone || Records::EntityStore.claimed_within?(Targets.contents(entity).to_a)

          findings << zone_inside(entity, path, holds_zone)
        end
        { "findings" => findings, "repairs" => [] }
      end

      def zone_inside(entity, path, holds_zone)
        name = Targets.native_name(entity)
        label = Reads.named?(name) ? "\"#{name}\"" : "An unnamed Group or component"
        what = holds_zone ? "a Zone" : "an object another feature owns, such as a Space"
        { "code" => "shading.zone_inside", "section" => SECTION, "object_id" => nil, "blocks_export" => false,
          "message" => "#{label} at path #{path.inspect} carries the shading mark and is or holds #{what}. " \
                       "The mark does not reach it, so its Faces stay as they are and are not shading." }
      end
    end
  end
end
