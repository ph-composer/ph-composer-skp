# frozen_string_literal: true

module PhComposer
  # A line group: a Group outside every Zone holding loose drawn lines, its record linking it to one record; an Edge
  # directly in it may carry an assignment. The mechanics every such feature shares, naming no feature: each call
  # takes the feature's Spec (context/EXTENSIBILITY.md, "Line groups").
  module LineGroups
    # A root-to-entity persistent-id path, as every reference here names one.
    PATH = { "type" => "array", "items" => { "type" => "integer" } }.freeze

    # One feature's line group: `label` and `edge_noun` (one word, also its step name) for messages, the two target
    # kinds, stores and record kinds, `link_key` (the group's linked-record field), `codes` (:outside_group,
    # :group_nested, :group_in_zone, :hidden) and `child_lookup`, a one-read index factory (`matching(entities, id)`).
    # The operations (GroupOperations, EdgeOperations) also read the linked record's kind and `link_label`, the type
    # an Edge names (`type_kind`, its field `type_key` and `type_label`) and `containment`, the query answering which
    # Zone holds a Group path.
    Spec = Struct.new(:label, :edge_noun, :group_kind, :edge_kind, :group_store, :edge_store, :group_record_kind,
                      :edge_record_kind, :link_key, :codes, :child_lookup, :link_kind, :link_label, :type_kind,
                      :type_key, :type_label, :containment, keyword_init: true) do
      # The group's `affected` kind and step-name stem: the label in snake case.
      def group_noun
        label.downcase.tr(" ", "_")
      end

      def code(name)
        codes.fetch(name)
      end

      def group?(entity)
        entity.is_a?(Sketchup::Group) && group_store.marks?(entity)
      end

      def edge?(entity)
        entity.is_a?(Sketchup::Edge) && edge_store.marks?(entity)
      end

      def validate_group!(record)
        found = group_record_kind.problems(record)
        return record if found.empty?

        raise CodedError.new("validation.failed", "A #{label} record is invalid: #{found.first}.", "findings" => found)
      end

      def validate_edge!(record)
        found = edge_record_kind.problems(record)
        return record if found.empty?

        raise CodedError.new("validation.failed", "A #{edge_noun} assignment record is invalid: #{found.first}.",
                             "findings" => found)
      end

      def new_group(id, link_id)
        { "id" => id, "schema_version" => 1, link_key => link_id, "user_data" => {}, "extension_data" => {} }
      end

      def group_identity(record)
        id = record && record["id"]
        Records::Identity.pattern(group_record_kind.id_prefix).match?(id.to_s) ? id : nil
      end

      def group_values(record)
        record ? group_record_kind.values(record) : {}
      end

      def edge_identity(record)
        id = record && record["id"]
        Records::Identity.pattern(edge_record_kind.id_prefix).match?(id.to_s) ? id : nil
      end

      def edge_values(record)
        record ? edge_record_kind.values(record) : {}
      end
    end

    module_function

    # The children of a Group or a component's definition, or nil for any other entity.
    def contents(entity)
      if entity.is_a?(Sketchup::Group)
        entity.entities
      elsif entity.is_a?(Sketchup::ComponentInstance)
        entity.definition.entities
      end
    end

    # `[record, nil]` for a JSON object, `[nil, nil]` for none and `[nil, problem]` for anything else, which a read
    # reports and a write refuses. It never raises for what is stored.
    def read(entity, store)
      value = entity.get_attribute(store.dictionary, store.key)
      return [nil, nil] if value.nil?
      return [nil, "The #{store.dictionary} record is not JSON text."] unless value.is_a?(String)

      record = store.read(entity)
      record.is_a?(Hash) ? [record, nil] : [nil, "The #{store.dictionary} record is not a JSON object."]
    rescue CodedError => error
      raise unless error.code == "record.unreadable"

      [nil, error.message]
    end

    # `record` as the engine's reference scan reads it: a metadata map that is not a JSON object holds no extension
    # envelope and so names nothing, and is left out rather than failing every delete in the Model.
    def scannable(record)
      record.reject { |key, value| %w[user_data extension_data].include?(key) && !value.is_a?(Hash) }
    end
  end
end
