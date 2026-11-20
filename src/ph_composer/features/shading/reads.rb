# frozen_string_literal: true

module PhComposer
  module Shading
    # Which Faces are shading and what their component is called, as pure functions over detached facts about
    # the Groups and components on a root path. No SketchUp read happens here; Targets builds the facts.
    module Reads
      # One Group or ComponentInstance on a root path, outermost first. `name` is the native name the rule
      # reads (an instance's own, else its definition's; a Group's own), `zone_name` the Zone's name when the
      # container is a Zone Group, else nil. `owned` is true when another feature claims it.
      Container = Struct.new(:path, :marked, :zone_name, :owned, :name, keyword_init: true) do
        def zone?
          !zone_name.nil?
        end
      end

      DEFAULT_NAME = "Shading"
      ZONE_SUFFIX = " Shading"

      module_function

      # The marked container a Face or container below `containers` is shading through, or nil. Walking outward
      # from the innermost, a Zone stops the walk before any mark above it, so a mark never reaches through a
      # Zone; an owned container anywhere on the path means nothing below it is shading, however near the mark.
      def inherited_from(containers)
        return nil if containers.any?(&:owned)

        containers.reverse_each do |container|
          return nil if container.zone?
          return container if container.marked
        end
        nil
      end

      # Whether a Face is a Shading Face: it carries the mark or inherits it, and neither it nor any container
      # above it is another feature's object.
      def shading_face?(marked:, owned:, containers:)
        return false if owned || containers.any?(&:owned)

        marked || !inherited_from(containers).nil?
      end

      # The component name a Shading Face exports under: the nearest enclosing container with a name,
      # walking outward; a Zone as that container gives its name followed by " Shading"; none gives "Shading".
      def component_name(containers)
        containers.reverse_each do |container|
          return "#{container.zone_name}#{ZONE_SUFFIX}" if container.zone?
          return container.name.strip if named?(container.name)
        end
        DEFAULT_NAME
      end

      def named?(name)
        name.is_a?(String) && !name.strip.empty?
      end
    end
  end
end
