# frozen_string_literal: true

module PhComposer
  module Records
    # A record kind keeps its own copies of what it was declared with, so a contributor that edits a
    # Field, a Reference or a schema Hash after building the kind changes nothing the kind enforces.
    module Fields
      # A frozen copy of a declared Field or Reference whose schema and strings are its own.
      def self.detached(declaration)
        declaration.class.new(**declaration.to_h.transform_values { |value| DeepCopy.frozen(value) }).freeze
      end
    end

    # One stored value of a record kind, declared as a JSON Schema (core/json_schema.rb). A number
    # carries its SI unit as `x-unit`, and its key names the unit too: `length_mm`.
    Field = Struct.new(:key, :schema, :required, keyword_init: true) do
      def reference?
        false
      end
    end

    # A field that names other records by id. `cardinality` is "one" (a string id) or "many" (a list
    # of ids). The engine checks that each target exists and remaps the ids when a duplicated
    # collection contains the target; nothing else about a string is ever read as a reference.
    Reference = Struct.new(:key, :target_kind, :cardinality, :required, keyword_init: true) do
      def reference?
        true
      end

      def schema
        id = { "type" => "string", "description" => "Id of a #{target_kind} record." }
        cardinality == "many" ? { "type" => "array", "items" => id } : id
      end

      # The ids this field holds in `values`, as a list whatever the cardinality.
      def ids(values)
        parents(values).flat_map { |parent| Array(parent[key.split(".").last]).compact }
      end

      # `values` with every id in `mapping` replaced by its counterpart; ids outside it are kept.
      def remap(values, mapping)
        copy = DeepCopy.call(values)
        leaf = key.split(".").last
        parents(copy).each do |parent|
          next unless parent.key?(leaf)

          current = parent[leaf]
          parent[leaf] = current.is_a?(Array) ? current.map { |id|
                                                  mapping.fetch(id, id)
                                                } : mapping.fetch(current, current)
        end
        copy
      end

      # Registration checks the declaration against the shape, so a typo cannot make
      # an incoming reference invisible. Entity targets with an open schema retain
      # their existing validator-owned contract.
      def declaration_problems(values_schema)
        unless key.is_a?(String) && /\A[a-z][a-z0-9_]*(\[\])?(\.[a-z][a-z0-9_]*(\[\])?)*\z/.match?(key)
          return ["reference key must be a dotted field path with optional [] array steps"]
        end
        return ["reference leaf must be a field; cardinality describes its ids"] if key.end_with?("[]")
        return ["reference cardinality must be one or many"] unless %w[one many].include?(cardinality)
        return [] unless values_schema.key?("properties")

        shape = values_schema
        key.split(".").each do |part|
          array = part.end_with?("[]")
          name = array ? part[0...-2] : part
          shape = shape.fetch("properties", {})[name]
          return ["reference #{key} is absent from the values schema"] unless shape
          next unless array

          return ["reference #{key} traverses a non-array field"] unless Array(shape["type"]).include?("array")

          shape = shape.fetch("items", {})
        end
        types = Array(shape["type"]) - ["null"]
        expected = cardinality == "many" ? "array" : "string"
        return ["reference #{key} must name a #{expected} field"] unless types == [expected]
        return [] unless cardinality == "many"
        return [] if Array(shape.fetch("items", {})["type"]) == ["string"]

        ["reference #{key} must contain string ids"]
      end

      private

      # Dotted keys traverse objects; [] traverses every member of an array. Only the
      # declared leaf is a reference, never another string with the same value.
      def parents(values)
        key.split(".")[0...-1].reduce([values]) do |nodes, part|
          array = part.end_with?("[]")
          name = array ? part[0...-2] : part
          nodes.flat_map do |node|
            next [] unless node.is_a?(Hash)

            child = node[name]
            array ? (child.is_a?(Array) ? child : []) : [child]
          end
        end.select { |node| node.is_a?(Hash) }
      end
    end

    # A nested object of a record kind that carries its own `user_data`: each member of an array of
    # objects reached by `path`, such as "layers[]", or "layers[].segments[]" for each Layer's
    # Layer-Segments. A member names itself by its "id", unique within its parent, so a part is addressed
    # by the id path from the record down: ["lyr_…"] for a Layer, ["lyr_…", "seg_…"] for one of its
    # Layer-Segments. Every shorter path is itself a declared part. A part carries no `extension_data`;
    # ph_composer.records.update_metadata writes its map (context/CONTRACTS.md, "Records and extension data").
    Part = Struct.new(:label, :path, keyword_init: true) do
      # The array field names from the record down: ["layers", "segments"].
      def steps
        path.split(".").map { |step| step.chomp("[]") }
      end

      # The member `part_ids` names in `record`, as the object inside it, or nil when there is none.
      def find(record, part_ids)
        return nil unless part_ids.length == steps.length

        steps.zip(part_ids).reduce(record) do |node, (key, id)|
          members = node.is_a?(Hash) ? node[key] : nil
          found = members.is_a?(Array) && members.find { |member| member.is_a?(Hash) && member["id"] == id }
          break nil unless found

          found
        end
      end

      # Every member at this path in `record`, as the objects inside it.
      def members(record)
        sibling_groups(record).flatten(1)
      end

      # The members at this path in `record`, one list per parent, so ids can be checked within each.
      def sibling_groups(record)
        parents = steps[0...-1].reduce([record]) do |nodes, key|
          nodes.flat_map { |node| node.is_a?(Hash) && node[key].is_a?(Array) ? node[key] : [] }
        end
        parents.select { |node| node.is_a?(Hash) && node[steps.last].is_a?(Array) }
               .map { |node| node[steps.last].select { |member| member.is_a?(Hash) } }
      end

      # Registration checks the path against the values schema and the kind's other parts, so a part a
      # typo hides, or one whose members cannot hold a map, refuses before anything is stored.
      def declaration_problems(values_schema, declared_paths)
        unless path.is_a?(String) && /\A[a-z][a-z0-9_]*\[\](\.[a-z][a-z0-9_]*\[\])*\z/.match?(path)
          return ["part path must be dotted array fields, each ending in []"]
        end

        parent = path.split(".")[0...-1].join(".")
        unless parent.empty? || declared_paths.include?(parent)
          return ["part #{path} needs its parent #{parent} declared as a part"]
        end

        shape = steps.reduce(values_schema) do |node, key|
          field = node.fetch("properties", {})[key]
          break nil unless field && Array(field["type"]).include?("array")

          field.fetch("items", {})
        end
        properties = shape && shape["properties"]
        return ["part #{path} must name an array of objects in the values schema"] unless properties
        return [] if properties.key?("id") && properties.key?("user_data")

        ["part #{path} members must declare id and user_data"]
      end
    end
  end
end
