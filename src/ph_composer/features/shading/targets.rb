# frozen_string_literal: true

module PhComposer
  module Shading
    # The live read behind every assign, clear and selection row: a root-to-entity persistent-id path resolved
    # strictly, then the detached facts Eligibility judges. Which containers are Zones comes from Zones' one walk
    # of its occurrences, and whether a Zone Face is classified from its registered host-context read; another
    # feature's object from the foundation's claim check. Reads only.
    module Targets
      HOST_CONTEXT = "ph_composer.zones.faces.host_context"
      REFERENCE = { "type" => "object", "additionalProperties" => false, "required" => ["entity_path"],
                    "properties" => {
                      "entity_path" => { "type" => "array", "items" => { "type" => "integer" }, "minItems" => 1,
                                         "description" => "The root-to-entity persistent-id path." }
                    } }.freeze

      module_function

      # The entities a root-to-entity path names, root first, each the one child of the one before with that
      # persistent id. It never searches by name or geometry: a step that is missing, repeated or not a
      # container refuses the path.
      def resolve!(model, path)
        entities = model.entities
        path.each_with_index.map do |persistent_id, index|
          matches = entities.to_a.select { |entity| entity.persistent_id == persistent_id }
          raise CodedError.new("target.not_found", "Entity #{persistent_id} no longer exists.") if matches.empty?
          if matches.length > 1
            raise CodedError.new("target.ambiguous", "Entity #{persistent_id} resolves more than once.")
          end

          entity = matches.first
          entities = contents(entity)
          if entities.nil? && index < path.length - 1
            raise CodedError.new("target.not_found", "Entity #{persistent_id} is not a Group or component, so " \
                                                     "the path cannot pass through it.")
          end
          entity
        end
      end

      # Eligibility::Facts for each path, in order, from one walk of the Zones and one host-context read. A path
      # that no longer resolves refuses the whole read.
      def facts(request, paths)
        model = request.model
        resolved = paths.map { |path| resolve!(model, path) }
        zones = zone_names(model)
        in_zone = paths.zip(resolved).select do |path, entities|
          entities.last.is_a?(Sketchup::Face) && zones.keys.any? { |zone| path[0, zone.length] == zone }
        end
        hosts = in_zone.map(&:first).each_slice(Pages::MAXIMUM_LIMIT).flat_map do |slice|
          request.query(HOST_CONTEXT, "paths" => slice).fetch("faces")
        end
        classified = hosts.reject { |row| row.dig("reference", "entity_id").nil? }.map { |row| row.fetch("path") }
        paths.zip(resolved).map { |path, entities| build(path, entities, zones, classified.include?(path)) }
      end

      # Every Zone occurrence's root path and name: the Group's native name, else its record's, as Zones shows
      # it. Zones does not walk into a cutting component, so a Zone record there names no Zone.
      def zone_names(model)
        Zones::Occurrences.zones(model).to_h do |zone|
          native = zone.entity.name
          [zone.path, Reads.named?(native) ? native : zone.record.fetch("name")]
        end
      end

      def build(path, entities, zones, classified)
        leaf = entities.last
        above = entities[0...-1]
        containers = above.each_with_index.map { |entity, index| container(entity, path[0..index], zones) }
        Eligibility::Facts.new(
          :path => path, :kind => Mark.kind(leaf), :marked => Mark.marked?(leaf), :containers => containers,
          :locked => entities.any? { |entity| locked?(entity) }, :shared => above.any? { |entity| shared?(entity) },
          :cutting => entities.any? { |entity| cutting?(entity) },
          :owned => containers.any?(&:owned) || owned?(leaf), :classified => classified,
          :zone => zones.key?(path),
          :zone_target => container?(leaf) && zones.keys.any? { |zone| zone[0, path.length] == path },
          :holds_owned => container?(leaf) && Records::EntityStore.claimed_within?(contents(leaf).to_a),
          :classified_inside => container?(leaf) && in_zone?(path, zones) ? classified_within(contents(leaf).to_a) : 0
        )
      end

      # Whether a root path lies strictly inside a Zone occurrence.
      def in_zone?(path, zones)
        zones.keys.any? { |zone| path.length > zone.length && path[0, zone.length] == zone }
      end

      # How many classified Zone Faces (a Face record present, readable or not) are among `entities` and inside
      # their Groups and components, at any depth, where a mark above would reach: never inside a cutting
      # component, another feature's object or a Zone. A Face carrying the mark itself is already shading.
      def classified_within(entities)
        entities.sum do |entity|
          if entity.is_a?(Sketchup::Face)
            Zones::Occurrences.classified_face?(entity) && !Mark.marked?(entity) ? 1 : 0
          elsif container?(entity) && !cutting?(entity) && !owned?(entity) && !Zones::Occurrences.zone_record?(entity)
            classified_within(contents(entity).to_a)
          else
            0
          end
        end
      end

      # The Reads::Container row for one Group or component at `path`; `zones` maps Zone paths to names.
      def container(entity, path, zones)
        Reads::Container.new(:path => path, :marked => Mark.marked?(entity), :owned => owned?(entity),
                             :zone_name => zones[path], :name => native_name(entity))
      end

      # A Group's own name; an instance's own name, else its definition's.
      def native_name(entity)
        own = entity.respond_to?(:name) ? entity.name.to_s : ""
        return own unless own.strip.empty? && entity.is_a?(Sketchup::ComponentInstance)

        entity.definition.name.to_s
      end

      # Another feature's own object: a claimed record on it, readable or not (Records::EntityStore.claimed?).
      # A Window Unit claims nothing; it is a cutting component, which `cutting?` refuses.
      def owned?(entity)
        Records::EntityStore.claimed?([entity])
      end

      def container?(entity)
        entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      end

      def contents(entity)
        if entity.is_a?(Sketchup::Group)
          entity.entities
        elsif entity.is_a?(Sketchup::ComponentInstance)
          entity.definition.entities
        end
      end

      def locked?(entity)
        entity.respond_to?(:locked?) && entity.locked?
      end

      # Storage more than one placement draws: a component definition placed more than once, or a Group copied
      # and not yet made unique. A component placed once is its own storage, so a Face inside it can be tagged.
      def shared?(entity)
        container?(entity) && entity.definition.instances.length > 1
      end

      def cutting?(entity)
        entity.is_a?(Sketchup::ComponentInstance) && entity.definition.behavior.cuts_opening?
      end
    end
  end
end
