# frozen_string_literal: true

require "json"

module PhComposer
  module Records
    # Canonical JSON stored on one explicitly resolved SketchUp entity. The caller owns occurrence
    # resolution; this store never scans the Model or substitutes a similarly named entity.
    class EntityStore
      attr_reader :dictionary, :key

      # Whether any of `entities` carries a claiming store's record: it is already a feature's own object, so
      # another feature must not turn it into something else or build on it. A store claims when it is
      # constructed with `claims_entity: true`, so this check names no feature (context/EXTENSIBILITY.md,
      # "Native menu items"). A record that does not claim, a Zone Face's for one, leaves the entity open to that.
      def self.claimed?(entities)
        stores = claiming.values
        entities.any? { |entity| stores.any? { |store| store.marks?(entity) } }
      end

      # Whether any of `entities`, or anything inside a Group or component among them at any depth, is claimed:
      # turning a container into something else takes its contents along, so a plain wrapper around a claimed
      # object is as taken as the object itself. A record that cannot be parsed still claims, since `marks?`
      # reads presence, so damaged data reads as occupied and is never repaired here.
      def self.claimed_within?(entities)
        pending = entities.to_a.dup
        seen = {}
        until pending.empty?
          entity = pending.pop
          return true if claimed?([entity])

          contents = container_contents(entity)
          next if contents.nil? || seen[contents.object_id]

          seen[contents.object_id] = true
          pending.concat(contents.to_a)
        end
        false
      end

      # What a selection is read against: the selected entities and every open context around them.
      def self.selection_claimed?(model)
        claimed?(model.selection.to_a + Array(model.active_path))
      end

      def self.container_contents(entity)
        if entity.is_a?(Sketchup::Group)
          entity.entities
        elsif entity.is_a?(Sketchup::ComponentInstance)
          entity.definition.entities
        end
      end
      private_class_method :container_contents

      # How many of the records `check_subtree_removal!` refuses for its detail names; `total` counts them all.
      FOREIGN_RECORD_DETAIL = 20

      # Refuses `target.foreign_records` when `entity`, at the root-to-entity persistent-id `path`, or anything
      # inside it at any depth carries a record of a store outside `owned`: erasing or exploding it would take
      # another owner's data with it. It reads every entity store's record by presence, valid or not, wherever
      # it sits, so a record no read takes as valid (a Zone record on a component) still counts.
      def self.check_subtree_removal!(entity, path, owned:)
        foreign = records_within(entity, path).reject { |store, _path| owned.include?(store) }
        return if foreign.empty?

        dictionaries = foreign.map { |store, _path| store.dictionary }.uniq
        raise CodedError.new("target.foreign_records",
                             "It holds data another feature owns (#{dictionaries.join(', ')}), which would go with " \
                             "it. Remove that data with its own feature first. Nothing was written.",
                             "total" => foreign.length,
                             "records" => foreign.first(FOREIGN_RECORD_DETAIL).map do |store, at|
                               { "dictionary" => store.dictionary, "key" => store.key, "path" => at }
                             end)
      end

      # Every [store, root-to-entity path] pair at or below `entity`, through Group and component contents.
      def self.records_within(entity, path)
        found = []
        pending = [[entity, path]]
        until pending.empty?
          current, at = pending.pop
          stores.each_value { |store| found << [store, at] if store.marks?(current) }
          contents = container_contents(current)
          contents&.each { |child| pending << [child, at + [child.persistent_id]] }
        end
        found.sort_by { |_store, at| at }
      end
      private_class_method :records_within

      def self.claim(store)
        claiming[[store.dictionary, store.key]] = store
      end

      def self.register(store)
        stores[[store.dictionary, store.key]] = store
      end

      def self.stores
        @stores ||= {}
      end
      private_class_method :stores

      def self.claiming
        @claiming ||= {}
      end
      private_class_method :claiming

      def initialize(dictionary, key: "record", claims_entity: false)
        @dictionary = Dictionaries.register(dictionary)
        @key = key
        self.class.register(self)
        self.class.claim(self) if claims_entity
      end

      # Whether `entity` holds a record here, readable or not.
      def marks?(entity)
        !entity.get_attribute(dictionary, key).nil?
      end

      def read(entity)
        text = entity.get_attribute(dictionary, key)
        text.nil? ? nil : JSON.parse(text)
      rescue JSON::ParserError
        raise CodedError.new("record.unreadable", "The #{dictionary} record is not valid JSON.")
      end

      def write(entity, record)
        entity.set_attribute(dictionary, key, CanonicalJson.generate(record))
      end

      def delete(entity)
        entity.delete_attribute(dictionary, key)
      end
    end
  end
end
