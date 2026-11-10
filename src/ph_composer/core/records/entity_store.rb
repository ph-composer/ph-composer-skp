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

      def self.claim(store)
        claiming[[store.dictionary, store.key]] = store
      end

      def self.claiming
        @claiming ||= {}
      end
      private_class_method :claiming

      def initialize(dictionary, key: "record", claims_entity: false)
        @dictionary = Dictionaries.register(dictionary)
        @key = key
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
