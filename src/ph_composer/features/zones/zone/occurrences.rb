# frozen_string_literal: true

module PhComposer
  module Zones
    # `locked_parent` is a locked container above the Zone on its path; a write refuses through it.
    ZoneOccurrence = Struct.new(:entity, :path, :transform, :record, :shared_definition, :nested, :locked_parent,
                                keyword_init: true) do
      def reference
        { "zone_id" => record.fetch("id"), "zone_path" => path.dup }
      end
    end

    # `entities` is the collection holding the Face, `transform` its parent-to-world transform.
    FaceOccurrence = Struct.new(:entity, :zone, :path, :transform, :entities, keyword_init: true) do
      def reference(entity_id = nil)
        {
          "zone_id" => zone.record.fetch("id"), "zone_path" => zone.path.dup,
          "entity_path" => path.dup, "entity_id" => entity_id
        }
      end
    end

    # Any drawing element inside a Zone occurrence, resolved by `Occurrences.resolve_element`: the shape
    # of a FaceOccurrence for an element of a kind Zones does not name.
    ElementOccurrence = Struct.new(:entity, :zone, :path, :transform, :entities, keyword_init: true) do
      def reference(entity_id = nil)
        { "zone_id" => zone.record.fetch("id"), "zone_path" => zone.path.dup, "entity_path" => path.dup,
          "entity_id" => entity_id }
      end
    end

    # What `Occurrences.containment` answers for one path: the holding Zone occurrence, the path from
    # inside it to the entity and the refusal a write through that path meets, or only the reason no Zone
    # holds it.
    Containment = Struct.new(:zone, :entity_path, :write_refusal, :reason, keyword_init: true)

    # Bounded occurrence reads for Zone and Face public operations. Resolution follows every supplied
    # parent-child path and durable id. It never searches by name or geometry to repair a stale target.
    module Occurrences
      module_function

      # An `index` is one walk of this Model, reused across a whole read phase (see index.rb). It is
      # always optional: without one every read walks the Model itself, exactly as before.
      def zones(model, index: nil)
        index ? index.check!(model).zones : scan_zones(model)
      end

      def scan_zones(model)
        found = []
        walk_zones(model.entities, [], identity, found, :shared => false, :inside_zone => false, :locked => false)
        found
      end

      # A Zone record on a ComponentInstance, as native Make Component on a Zone Group leaves it, is no Zone
      # occurrence: every read passes it by, and this names each one, with the way back, for the reads and
      # export preflight to report. The other Zones stay readable.
      def component_findings(model)
        strays = []
        walk_zones(model.entities, [], identity, [], :shared => false, :inside_zone => false, :locked => false,
                                                     :strays => strays)
        # One finding per Zone: the placements of a copied component share the one record.
        strays.map { |entity, path| [Names.read(entity), path] }.uniq { |record, _path| record.fetch("id") }
              .map do |record, path|
          { "code" => "zone.component", "reference" => { "zone_id" => record.fetch("id"), "entity_path" => path },
            "message" => "Zone \"#{record.fetch('name')}\" is now a component, so it is not read as a Zone. Undo " \
                         "Make Component to get it back as it was. Without Undo, explode the component: Restore is " \
                         "then offered if its Faces can be regrouped, recovering its id, Building-Segment and Level." }
        end
      end

      def resolve_zone(model, reference, mutable: false, index: nil)
        zone_id = reference.fetch("zone_id")
        path = integer_path(reference.fetch("zone_path"))
        matching_ids = zones(model, :index => index).select { |zone| zone.record["id"] == zone_id }
        raise_target("target.not_found", "Zone #{zone_id} does not exist.") if matching_ids.empty?
        raise_target("target.ambiguous", "Zone #{zone_id} occurs more than once.") if matching_ids.length > 1

        zone = matching_ids.first
        raise_target("target.changed", "The Zone occurrence path has changed.") unless zone.path == path
        writable_zone!(zone) if mutable
        zone
      end

      # What a write through a Zone occurrence refuses that its own path shows.
      def writable_zone!(zone)
        if zone.shared_definition
          raise_target("target.shared_definition", "That Zone is inside shared component storage.")
        end
        raise_target("target.wrong_hierarchy", "A Zone cannot be nested inside another Zone.") if zone.nested
        raise_target("target.locked", "A Group containing the Zone is locked.") if zone.locked_parent
      end

      def faces(zone, index: nil)
        index ? index.faces(zone) : scan_faces(zone)
      end

      def scan_faces(zone)
        found = []
        walk_faces(zone.entity.entities, [], zone.transform, zone, found)
        found
      end

      def resolve_face(model, reference, mutable: false, allow_unassigned: false, index: nil)
        zone = resolve_zone(model, reference, :mutable => mutable, :index => index)
        occurrence = face_at(zone, reference.fetch("entity_path"), :mutable => mutable)
        entity = occurrence.entity
        record = face_record(entity)
        expected_id = reference["entity_id"]
        if expected_id
          raise_target("target.not_found", "Face #{expected_id} has no assignment record.") unless record
          raise_target("target.changed", "The Face identity has changed.") unless record["id"] == expected_id
          copies = faces_with_id(model, expected_id, :index => index)
          raise_target("target.ambiguous", "Face #{expected_id} occurs more than once.") if copies.length > 1
        elsif record && !allow_unassigned
          raise_target("target.changed", "The Face now has an assignment record.")
        end

        stamped_for!(zone, entity)
        unlocked_zone!(zone) if mutable
        occurrence
      end

      def stamped_for!(zone, entity)
        stamp = STAMP_STORE.read(entity)
        return unless stamp && stamp["zone_id"] != zone.record["id"]

        raise_target("target.wrong_zone", "The Face stamp names another Zone.")
      end

      def unlocked_zone!(zone)
        raise_target("target.locked", "The Zone is locked.") if zone.entity.respond_to?(:locked?) && zone.entity.locked?
      end

      # The refusal a write to this Face occurrence meets from its path alone, as `{ code, message }`, or
      # nil. It runs the strict resolver's writable checks over the path without walking the Model, so
      # it cannot see a duplicated Zone or Face id: a pointer move may ask it, and the write itself
      # still resolves strictly.
      def write_refusal(occurrence)
        element_write_refusal(occurrence.zone, occurrence.path)
      end

      # The same refusal for any drawing element inside a Zone occurrence, by its path inside the Zone.
      # `noun` is the caller's word for the element, used in the messages.
      def element_write_refusal(zone, entity_path, noun: "Face")
        writable_zone!(zone)
        entity, = resolve_face_path(zone, integer_path(entity_path), true, :noun => noun)
        stamped_for!(zone, entity)
        unlocked_zone!(zone)
        nil
      rescue CodedError => error
        { "code" => error.code, "message" => error.message }
      end

      # A Face-shaped reference (`zone_id`, `zone_path`, `entity_path`) resolved strictly to the drawing
      # element it names, of any kind: the Zone by id and path, every step inside it, and, when `mutable`,
      # what a write through that path refuses. It reads no record on the element and checks no kind; an
      # owner storing records on other elements checks both itself. Returns an ElementOccurrence. Its
      # `index:` is a Zones::Index, as for the Zone and Face targets.
      def resolve_element(model, reference, noun:, mutable: false, index: nil)
        zone = resolve_zone(model, reference, :mutable => mutable, :index => index)
        path = integer_path(reference.fetch("entity_path"))
        raise_target("target.not_found", "The #{noun} path is empty.") if path.empty?

        entity, transform, entities = resolve_face_path(zone, path, mutable, :noun => noun)
        stamped_for!(zone, entity)
        unlocked_zone!(zone) if mutable
        ElementOccurrence.new(:entity => entity, :zone => zone, :path => path, :transform => transform,
                              :entities => entities)
      end

      # The Zone reference target's `locate:` (Records::ReferenceTarget): the strict resolver, so a
      # feature requiring Zones reaches the live Zone Group publicly, with the same refusals. As for
      # every located entity, `transform` is the Zone's parent-to-world transform; the Zone's contents
      # map to world through `transform * entity.transformation`. Its read-phase `index:` is a Zones::Index.
      def locate_zone(model, reference, mutable:, index: nil)
        zone = resolve_zone(model, reference, :mutable => mutable, :index => index)
        unlocked_zone!(zone) if mutable
        parent_path = zone.path[0...-1]
        Records::LocatedEntity.new(:kind => REFERENCE_KIND, :reference => DeepCopy.call(reference),
                                   :entity => zone.entity, :entities => collection_at(model, parent_path),
                                   :transform => zone.transform * zone.entity.transformation.inverse,
                                   :parent_path => parent_path)
      end

      # The nested containers inside one Zone occurrence: each stamped Group the Face walk stops at, as
      # `[entity, path]` with the path inside the Zone. A nested Zone and a cutting component bound it, as
      # they bound the walk.
      def containers(zone)
        found = []
        pending = [[zone.entity.entities, []]]
        until pending.empty?
          entities, path = pending.shift
          entities.each do |entity|
            next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
            next if ZONE_STORE.read(entity) || cutting_component?(entity)

            child_path = path + [entity.persistent_id]
            if container?(entity)
              found << [entity, child_path]
            else
              pending << [contents(entity), child_path]
            end
          end
        end
        found
      end

      # The Face reference target's `locate:` (Records::ReferenceTarget): the owner's strict resolution,
      # so a reference read before the Face gained a record refuses rather than naming a different one.
      # Its read-phase `index:` is a Zones::Index.
      def locate_face(model, reference, mutable:, index: nil)
        occurrence = resolve_face(model, reference, :mutable => mutable, :index => index)
        Records::LocatedEntity.new(:kind => Faces::REFERENCE_KIND, :reference => DeepCopy.call(reference),
                                   :entity => occurrence.entity, :entities => occurrence.entities,
                                   :transform => occurrence.transform,
                                   :parent_path => occurrence.zone.path + occurrence.path[0...-1])
      end

      # The Face occurrence a root-to-Face persistent-id path names, or nil when the path no longer
      # resolves uniquely or names no Zone Face. A read, under the same rule as `occurrence_for_path`.
      def occurrence_at(model, path)
        found = entities_along(model, path)
        found && occurrence_for_path(found)
      end

      # Which Zone occurrence holds the entity a root-to-entity persistent-id path names, read along that
      # path alone, as a Containment. The Zone is the innermost one above the entity, by the rule
      # `occurrence_for_path` applies to Faces; any drawing element may be the leaf. Without a Zone it
      # carries the reason: `not_found` (a step missing or repeated), `not_a_drawing_element`,
      # `cutting_instance` (a cutting component above it), `outside_zone`, or `nested_container` (a stamped
      # container between the Zone and it). Like `occurrence_for_path` it proves no identity; a write
      # still resolves strictly.
      def containment(model, path)
        entities = entities_along(model, path)
        return Containment.new(:reason => "not_found") unless entities

        zone, inside, reason = holding(entities)
        return Containment.new(:reason => reason) unless zone

        entity_path = inside.map(&:persistent_id)
        Containment.new(:zone => zone, :entity_path => entity_path,
                        :write_refusal => element_write_refusal(zone, entity_path, :noun => entities.last.typename))
      end

      # The entities a root-to-entity path names, each the unique child of the one before, or nil when
      # a step is missing or repeated.
      def entities_along(model, path)
        entities = model.entities
        integer_path(path).map do |persistent_id|
          matches = entities.to_a.select { |entity| entity.persistent_id == persistent_id }
          return nil unless matches.length == 1

          entity = matches.first
          entities = if entity.is_a?(Sketchup::Group)
                       entity.entities
                     elsif entity.is_a?(Sketchup::ComponentInstance)
                       entity.definition.entities
                     end
          entity
        end
      end

      # The occurrence one picked instance path names, or nil when the path reaches no Face or the
      # Face lies inside no Zone. Nothing here walks the Model: the pick already knows the whole
      # root-to-leaf path, and a viewport tool picks once per pointer move.
      #
      # This is the read half only. It answers what the pointer is over; it proves nothing about
      # identity, ambiguity or whether the Zone can be written to. A gesture built from these
      # references still resolves each one through `resolve_face` before anything is written, which
      # is where a duplicated id or a changed path is caught.
      def occurrence_for_path(path)
        entities = Array(path)
        face = entities.last
        return nil unless face.is_a?(Sketchup::Face)

        zone, inside, = holding(entities)
        return nil unless zone

        transform = inside[0...-1].reduce(zone.transform) { |carried, entity| carried * entity.transformation }
        FaceOccurrence.new(:entity => face, :zone => zone, :path => inside.map(&:persistent_id),
                           :transform => transform, :entities => contents(entities[-2]))
      end

      # The Zone occurrence holding the last of a root-to-entity list and the entities from inside it to
      # the leaf, as `[zone, inside, nil]`, or `[nil, nil, reason]` (see `containment`).
      def holding(entities)
        return [nil, nil, "not_a_drawing_element"] unless entities.last.is_a?(Sketchup::Drawingelement)
        return [nil, nil, "cutting_instance"] if entities[0...-1].any? { |entity| cutting_component?(entity) }

        # The innermost Zone above the leaf, because that is the one whose Faces this Face is among:
        # `walk_faces` stops descending at a nested Zone, so an outer Zone does not own it. Taking
        # the outer one instead would build a reference the resolver accepts, since it descends a
        # Group without checking for a Zone record, and the gesture would stamp the Face with the
        # wrong Zone.
        zone_index = entities[0...-1].rindex { |entity| entity.is_a?(Sketchup::Group) && ZONE_STORE.read(entity) }
        return [nil, nil, "outside_zone"] unless zone_index

        inside = entities[(zone_index + 1)..-1]
        return [nil, nil, "nested_container"] if inside[0...-1].any? { |entity| container?(entity) }

        zone = zone_for_path(entities[0..zone_index],
                             entities[0...zone_index].any? { |entity| ZONE_STORE.read(entity) })
        [zone, inside, nil]
      end

      # The Zone occurrence for a root-to-Zone entity path, composed exactly as `walk_zones` does.
      def zone_for_path(entities, nested)
        transform = entities.reduce(identity) { |carried, entity| carried * entity.transformation }
        ZoneOccurrence.new(:entity => entities.last, :path => entities.map(&:persistent_id),
                           :transform => transform, :record => Schema.validate!(Names.read(entities.last)),
                           :shared_definition => entities.any? { |entity| shared_storage?(entity) },
                           :nested => nested, :locked_parent => entities[0...-1].any?(&:locked?))
      end

      # One Face inside an already-resolved Zone occurrence, by path alone. Identity repair needs
      # this: the Zone id it is about to replace is duplicated, so the id-keyed resolver would
      # refuse the very ambiguity the repair exists to remove.
      def face_at(zone, entity_path, mutable: false)
        path = integer_path(entity_path)
        entity, transform, entities = resolve_face_path(zone, path, mutable)
        unless entity.is_a?(Sketchup::Face)
          raise_target("target.wrong_kind", "The occurrence does not resolve to a Face.")
        end

        FaceOccurrence.new(:entity => entity, :zone => zone, :path => path, :transform => transform,
                           :entities => entities)
      end

      # Every container on the path is checked the way `walk_faces` bounds a Zone's Faces: a child
      # carrying a Zone record, or a Group carrying a Zone stamp, owns what is inside it, so a path
      # through one names a Face this Zone does not own, for reads and writes alike. A Group whose
      # definition another Group shares is storage both placements write through, so a mutable path
      # refuses it and asks for it to be opened, which gives that placement its own definition. The
      # rule holds for any element at the end of the path; `noun` names it in the messages.
      def resolve_face_path(zone, path, mutable, noun: "Face")
        current = zone.entity.entities
        transform = zone.transform
        entity = nil
        path.each_with_index do |persistent_id, index|
          entity = unique_entity(current, persistent_id)
          break if index == path.length - 1

          if ZONE_STORE.read(entity)
            raise_target("target.wrong_hierarchy", "The #{noun} path crosses another Zone.")
          elsif container?(entity)
            raise_target("target.wrong_hierarchy", "The #{noun} is inside a nested container, not in the Zone itself.")
          elsif entity.is_a?(Sketchup::ComponentInstance)
            if cutting_component?(entity)
              raise_target("target.wrong_kind", "Cutting component geometry is not part of the Zone.")
            end
            raise_target("target.shared_definition", "That #{noun} is inside shared component storage.") if mutable
            current = entity.definition.entities
          elsif entity.is_a?(Sketchup::Group)
            raise_target("target.locked", "The #{noun} is inside a locked Group.") if mutable && entity.locked?
            if mutable && shared_storage?(entity)
              raise_target("target.shared_definition",
                           "That #{noun} is inside a Group shared with a copy. Open that Group with Edit Group, or " \
                           "double-click it, then close it, and try again.")
            end
            current = entity.entities
          else
            raise_target("target.wrong_kind", "The occurrence path passes through a non-container entity.")
          end
          transform *= entity.transformation
        end
        [entity, transform, current]
      end

      # The identity of one Face occurrence inside a gesture: the full root-to-Face persistent-id
      # path. Two references naming the same Face deduplicate to one affected target.
      def key(reference)
        [integer_path(reference.fetch("zone_path")), integer_path(reference.fetch("entity_path"))]
      end

      def active_path(model)
        Array(model.active_path).map(&:persistent_id)
      end

      def entities_at(model, path)
        Operations::EntityScope.new(path).resolve(model)
      end

      def face_record(face)
        Faces::FACE_STORE.read(face)
      end

      def faces_with_id(model, id, index: nil)
        return index.check!(model).faces_with_id(id) if index

        zones(model).flat_map { |zone| faces(zone) }.select do |face|
          face_record(face.entity)&.fetch("id", nil) == id
        end
      end

      def default_segment(model)
        path = model.path.to_s
        name = path.empty? ? model.title.to_s : File.basename(path, File.extname(path))
        name.empty? ? "Building" : name
      end

      def identity
        Geom::Transformation.new
      end

      def integer_path(value)
        Array(value).map { |id| Integer(id) }
      rescue ArgumentError, TypeError
        raise_target("params.invalid", "Occurrence paths contain only persistent-id integers.")
      end

      def unique_entity(entities, persistent_id)
        matches = entities.to_a.select { |candidate| candidate.persistent_id == persistent_id }
        raise_target("target.not_found", "Entity #{persistent_id} no longer exists.") if matches.empty?
        raise_target("target.ambiguous", "Entity #{persistent_id} resolves more than once.") if matches.length > 1

        matches.first
      end

      # `shared`, `inside_zone` and `locked` are what the containers above `entities` pass down: shared
      # storage, an enclosing Zone, and a lock. `strays`, when given, collects [entity, path] for each Zone
      # record on a ComponentInstance (component_findings).
      def walk_zones(entities, path, transform, found, shared:, inside_zone:, locked:, strays: nil)
        entities.each do |entity|
          next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
          next if cutting_component?(entity)

          child_path = path + [entity.persistent_id]
          child_transform = transform * entity.transformation
          record = Names.read(entity)
          child_shared = shared || shared_storage?(entity)
          if record && !entity.is_a?(Sketchup::Group)
            Schema.validate!(record)
            strays&.push([entity, child_path])
          elsif record
            Schema.validate!(record)
            found << ZoneOccurrence.new(:entity => entity, :path => child_path, :transform => child_transform,
                                        :record => record, :shared_definition => child_shared,
                                        :nested => inside_zone, :locked_parent => locked)
          end
          child_entities = entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
          # A stray record is no Zone, so a Zone Group inside it is not nested.
          zone = !record.nil? && entity.is_a?(Sketchup::Group)
          walk_zones(child_entities, child_path, child_transform, found,
                     :shared => child_shared, :inside_zone => inside_zone || zone,
                     :locked => locked || entity.locked?, :strays => strays)
        end
      end

      # Whether this container's contents are storage more than one occurrence writes through.
      #
      # Copying a Group in SketchUp does not copy what is inside it: both Groups become instances of
      # one definition and share every Face in it, while each instance keeps its own Zone record.
      # So a copied Zone has a duplicated id and shared members at the same time, and editing either
      # occurrence's Faces edits the other's. Measured on 26.1.188, 2026-09-20; before this, a
      # copied Zone read as ambiguous but not shared, and repairing it rewrote the original's Faces.
      def shared_storage?(entity)
        return true if entity.is_a?(Sketchup::ComponentInstance)
        return false unless entity.respond_to?(:definition)

        definition = entity.definition
        definition.respond_to?(:instances) && definition.instances.length > 1
      end

      def walk_faces(entities, path, transform, zone, found)
        entities.each do |entity|
          child_path = path + [entity.persistent_id]
          if entity.is_a?(Sketchup::Face)
            found << FaceOccurrence.new(:entity => entity, :zone => zone, :path => child_path,
                                        :transform => transform, :entities => entities)
          elsif entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
            next if ZONE_STORE.read(entity) || cutting_component?(entity) || container?(entity)

            child_entities = entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
            walk_faces(child_entities, child_path, transform * entity.transformation, zone, found)
          end
        end
      end

      # The collection a root-to-container path names, through Groups and ComponentInstances alike.
      def collection_at(model, path)
        path.reduce(model.entities) { |entities, persistent_id| contents(unique_entity(entities, persistent_id)) }
      end

      def contents(container)
        container.is_a?(Sketchup::Group) ? container.entities : container.definition.entities
      end

      def cutting_component?(entity)
        entity.is_a?(Sketchup::ComponentInstance) && entity.definition.behavior.cuts_opening?
      end

      # A Group inside a Zone that carries a Zone stamp is a nested authoring container: the feature
      # that stamped it owns what it holds, so none of it is a Zone Face, whichever Zone the stamp
      # names. Presence decides, so an unreadable stamp still marks one. Only Groups: a stamped Face
      # is a classified Zone Face (context/CONTRACTS.md, "Zones geometry rules").
      def container?(entity)
        entity.is_a?(Sketchup::Group) && !entity.get_attribute(STAMP_DICTIONARY, STAMP_STORE.key).nil?
      end

      def raise_target(code, message)
        raise CodedError.new(code, message)
      end
      private_class_method :resolve_face_path, :walk_zones, :holding, :entities_along, :walk_faces, :raise_target,
                           :zone_for_path, :cutting_component?, :container?, :contents, :collection_at, :writable_zone!,
                           :unlocked_zone!, :stamped_for!
    end
  end
end
