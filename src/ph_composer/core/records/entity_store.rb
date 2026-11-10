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

      # What a selection is read against: the selected entities and every open context around them.
      def self.selection_claimed?(model)
        claimed?(model.selection.to_a + Array(model.active_path))
      end

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
