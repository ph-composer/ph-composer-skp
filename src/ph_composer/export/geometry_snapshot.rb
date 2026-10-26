# frozen_string_literal: true

require "json"

module PhComposer
  module Export
    # One detached traversal of the Model for every geometry contributor. Entries contain no live
    # SketchUp object, so a contributor cannot mutate the Model or rescan a definition behind export.
    class GeometrySnapshot
      Entry = Struct.new(:kind, :path, :transform, :dictionaries, :geometry, :native_name, :native,
                         :keyword_init => true) do
        def record(dictionary)
          text = dictionaries.dig(dictionary, "record")
          return nil if text.nil?
          unless text.is_a?(String)
            raise Blocked.new("record.unreadable", "The #{dictionary} entity record is not JSON text.")
          end

          record = JSON.parse(text)
          unless record.is_a?(Hash)
            raise Blocked.new("record.unreadable", "The #{dictionary} entity record is not a JSON object.")
          end

          record
        rescue JSON::ParserError
          raise Blocked.new("record.unreadable", "The #{dictionary} entity record is not valid JSON.")
        end

        def to_h
          { "kind" => kind, "path" => path, "transform" => transform,
            "dictionaries" => dictionaries, "geometry" => geometry&.to_h }
        end
      end

      # One Edge occurrence in world SI metres. Its vertex and Face ids are the container's own, so
      # Edges connect by a shared vertex id within one occurrence; coincident points in different
      # containers are not connected. A sibling Face's path is the Edge's path with the Face id last.
      EdgeGeometry = Struct.new(:points_m, :vertex_ids, :face_ids, :keyword_init => true) do
        def self.capture(edge, transform)
          FaceGeometry.check_transform!(transform.to_a)
          points = [edge.start, edge.end].map do |vertex|
            point = vertex.position.transform(transform)
            FaceCapture.point_m(point).freeze
          end
          unless points.flatten.all?(&:finite?)
            raise CodedError.new("geometry.invalid", "An Edge has a non-finite coordinate.")
          end

          new(:points_m => points.freeze, :vertex_ids => [edge.start, edge.end].map(&:persistent_id).freeze,
              :face_ids => edge.faces.map(&:persistent_id).sort.freeze)
        end

        def to_h
          { "points_m" => points_m, "vertex_ids" => vertex_ids, "face_ids" => face_ids }
        end
      end

      attr_reader :entries, :revision, :model_dictionaries

      # A traversal resumed by UI timers. One slice bounds both entity count and elapsed host work;
      # a single native Face capture cannot be interrupted, so it remains the smallest work unit.
      class Cursor
        attr_reader :entries, :count, :model_dictionaries

        def initialize(model)
          @model_dictionaries = GeometrySnapshot.read_dictionaries(model)
          @walk = GeometrySnapshot.enum_for(:walk, model.entities, [], Geom::Transformation.new, {})
          @entries = []
          @count = 0
          @done = false
        end

        def advance(limit: 100, budget_seconds: 0.008)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          limit.times do
            entry = @walk.next
            @entries << entry if entry
            @count += 1
            break if Process.clock_gettime(Process::CLOCK_MONOTONIC) - started >= budget_seconds
          end
          done?
        rescue StopIteration
          @done = true
        end

        def done?
          @done
        end
      end

      def self.capture(model, revision:)
        cursor = Cursor.new(model)
        cursor.advance until cursor.done?
        new(cursor.entries, revision, :model_dictionaries => cursor.model_dictionaries)
      end

      # Yields an Entry for each entity the snapshot keeps and nil as a progress tick: for an entity it does
      # not keep, and for each child read while capturing a component definition the first time it is met
      # (native_facts). Cursor#count therefore measures traversal work, not entities. Faces and Edges inside
      # a cutting component are walked but not captured (`capture_geometry` false): the component's own
      # definition facts describe them.
      def self.walk(entities, path, transform, definitions = {}, capture_geometry: true, &block)
        entities.each do |entity|
          child_path = path + [entity.persistent_id]
          dictionaries = read_dictionaries(entity)
          if entity.is_a?(Sketchup::Face)
            entry = if capture_geometry
                      Entry.new(:kind => "face", :path => child_path.freeze, :transform => transform.to_a.freeze,
                                :dictionaries => dictionaries, :geometry => FaceCapture.call(entity, transform))
                    end
            block.call(entry)
          elsif entity.is_a?(Sketchup::Edge)
            entry = if capture_geometry
                      Entry.new(:kind => "edge", :path => child_path.freeze, :transform => transform.to_a.freeze,
                                :dictionaries => dictionaries, :geometry => EdgeGeometry.capture(entity, transform))
                    end
            block.call(entry)
          elsif entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
            child_transform = transform * entity.transformation
            kind = entity.is_a?(Sketchup::Group) ? "group" : "component_instance"
            block.call(Entry.new(:kind => kind, :path => child_path.freeze, :transform => child_transform.to_a.freeze,
                                 :dictionaries => dictionaries, :geometry => nil,
                                 :native_name => entity.name.to_s.dup.freeze,
                                 :native => native_facts(entity, definitions, &block)))
            cuts = entity.is_a?(Sketchup::ComponentInstance) && entity.definition.behavior.cuts_opening?

            child_entities = entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
            walk(child_entities, child_path, child_transform, definitions,
                 :capture_geometry => capture_geometry && !cuts, &block)
          else
            block.call(nil)
          end
        end
      end

      def self.native_facts(entity, definitions, &block)
        return nil unless entity.is_a?(Sketchup::ComponentInstance)

        definition = entity.definition
        # A detached Face capture remains the smallest resumable native work unit.
        facts = definitions[definition.persistent_id] ||= definition_facts(definition) { block.call(nil) }
        { "definition" => facts, "glued_to_id" => entity.glued_to&.persistent_id }.freeze
      end

      # One component definition as detached facts: its dictionaries, behaviour and each direct child
      # Face or Edge in definition coordinates. Authoring captures a live definition the same way, so
      # authoring and export compare one shape. The block, if given, runs after each child.
      def self.definition_facts(definition)
        children = definition.entities.map do |child|
          captured = definition_entity(child)
          yield if block_given?
          captured
        end
        { "id" => definition.persistent_id, "dictionaries" => read_dictionaries(definition),
          "cuts_opening" => definition.behavior.cuts_opening?, "is2d" => definition.behavior.is2d?,
          "entities" => children.freeze }.freeze
      end

      def self.definition_entity(entity)
        result = { "dictionaries" => read_dictionaries(entity) }
        if entity.is_a?(Sketchup::Face)
          result.merge("kind" => "face", "geometry" => FaceCapture.call(entity, Geom::Transformation.new).to_h)
        elsif entity.is_a?(Sketchup::Edge)
          points = [entity.start.position, entity.end.position].map do |point|
            FaceCapture.point_m(point).freeze
          end
          result.merge("kind" => "edge", "points_m" => points.freeze)
        else
          result.merge("kind" => "other")
        end.freeze
      end
      private_class_method :native_facts, :definition_entity

      # Every PH-Composer dictionary on one entity or Model, detached. Public for Cursor, which reads
      # the Model's own dictionaries before it walks.
      def self.read_dictionaries(entity)
        Array(entity.attribute_dictionaries).each_with_object({}) do |dictionary, result|
          next unless dictionary.name.start_with?("#{DICTIONARY_PREFIX}.")

          values = {}
          dictionary.each { |key, value| values[key.to_s] = DeepCopy.call(value) }
          result[dictionary.name] = values.freeze
        end.freeze
      end

      def initialize(entries, revision, model_dictionaries: {})
        @entries = entries.freeze
        @revision = revision
        @model_dictionaries = model_dictionaries.freeze
      end

      def records(dictionary, kind: nil)
        entries.filter_map do |entry|
          next if kind && entry.kind != kind

          record = entry.record(dictionary)
          [entry, record] if record
        end
      end

      def entry_at(path, kind: nil)
        matches = entries.select { |entry| entry.path == path && (!kind || entry.kind == kind) }
        if matches.length > 1
          raise Blocked.new("target.ambiguous", "An export occurrence path resolves more than once.")
        end

        matches.first
      end

      def descendants(parent, kind: nil)
        entries.select { |entry| (!kind || entry.kind == kind) && contains?(parent, entry) }
      end

      # Whether `entry` lies strictly inside `parent`, by occurrence path.
      def contains?(parent, entry)
        entry.path.length > parent.path.length && entry.path[0, parent.path.length] == parent.path
      end
    end

    # The existing metadata-safe record reader plus the one shared geometry snapshot.
    class SnapshotReader
      attr_reader :snapshot

      def initialize(records, snapshot, registry: Registry.current)
        @records = records
        @snapshot = snapshot
        @registry = registry
        @projections = {}
        @reading = nil
      end

      # Contributors share detached projections without repeating assessment or native reads.
      def projection(key)
        @projections.fetch(key) { @projections[key] = yield }
      end

      # Runs the block as the contributor for `section`: findings name it, and `section` reads only what
      # it declared.
      def within(section, &block)
        previous = @reading
        @reading = section
        @records.within(section, &block)
      ensure
        @reading = previous
      end

      # The detached projection another contributor registered, computed once per export. The reading
      # contributor must declare `name` in its `requires:`; registration has checked the layer.
      def section(name)
        reading = @registry.export_contributors[@reading]
        unless reading && reading.requires.include?(name)
          raise InternalError, "#{@reading.inspect} reads #{name} without declaring it in requires."
        end

        provider = @registry.export_contributors.fetch(name)
        raise InternalError, "#{name} registers no projection." unless provider.projection

        projection([:section, name]) { within(name) { provider.projection.call(self) } }
      end

      def records(*arguments, **keywords)
        @records.records(*arguments, **keywords)
      end

      def entity_record(record, fields:, target_kind: nil, path: nil, user_data: false)
        @records.entity_record(record, :fields => fields, :target_kind => target_kind, :path => path,
                                       :user_data => user_data)
      end

      def capture_entity(record, target_kind:, path:)
        @records.capture_entity(record, :target_kind => target_kind, :path => path)
      end

      # The declared fields of `namespace` envelopes on `target_kind` occurrences, as
      # `{"id", "path", "payload"}` rows; the reading contributor must hold that claim.
      def entity_projection(namespace, target_kind)
        @records.entity_projection(namespace, target_kind, :reader => @reading)
      end

      def findings
        @records.findings
      end

      def note(code, object_id, message)
        @records.note(code, object_id, message)
      end

      def reconcile!
        @records.reconcile!
      end
    end
  end
end
