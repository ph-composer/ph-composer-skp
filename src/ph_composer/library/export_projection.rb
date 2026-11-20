# frozen_string_literal: true

require_relative "dependencies"
require_relative "file_provider"
require_relative "library_file"

module PhComposer
  module Library
    # Detached, adapter-owned semantic projection. Record metadata is reviewed by field name only;
    # neither extension payloads nor a provider's transport configuration enter a library file. A written row's
    # dependencies (Dependencies) are written with it, whatever the selection, so the file can supply them.
    module ExportProjection
      # Which local records an export reads: `scope` is "all" or "selected", `records` the selected ones,
      # `kinds` the wire kinds written.
      Selection = Struct.new(:scope, :records, :kinds, keyword_init: true)
      # What one build collects: rows by wire kind, record origins by wire kind and id, and omissions.
      Collected = Struct.new(:rows, :origins, :omissions, keyword_init: true)

      module_function

      def build(request)
        selection = selection(request)
        kinds = selection.kinds
        declarations = request.registry.library_kinds.values
        collected = Collected.new(:rows => kinds.sort.to_h { |kind| [kind, []] }, :origins => {}, :omissions => [])
        targets(request, selection.scope, selection.records).each do |record_kind, id|
          declaration = declarations.find { |row| row.record_kind == record_kind }
          unless declaration
            collected.omissions << omission(record_kind, id, [], "unsupported_kind")
            next
          end
          next unless kinds.include?(declaration.adapter.wire_kind)

          collect(request, declaration, record_kind, id, collected)
        end
        add_dependencies(request, declarations, collected)
        rows = collected.rows.sort.to_h
        origins = collected.origins
        omissions = collected.omissions
        if rows.values.sum(&:length) > FileProvider::MAX_ROWS
          raise Error.new("library.catalog_too_many_rows", "The library export exceeds the 20,000 row limit.")
        end

        rows.each_value { |items| items.sort_by! { |row| row.fetch("id") } }
        versions = rows.keys.to_h do |kind|
          [kind, declarations.find { |row| row.adapter.wire_kind == kind }.adapter.wire_version]
        end
        projection = { "kinds" => rows, "kind_schema_versions" => versions, "record_origins" => origins,
                       "omissions" => omissions }
        projection["projection_digest"] = CanonicalJson.digest(projection)
        projection
      end

      # One local record's library row, its origin, and the omissions that say what the file leaves out.
      def collect(request, declaration, record_kind, id, collected)
        adapter = declaration.adapter
        record = read_record(request, record_kind, id)
        row = reverse(adapter, record)
        # A row a reader would skip for its label is reported, not written.
        unless Admission.label_for(adapter, mapped_values(adapter, row))
          collected.omissions << omission(record_kind, id, [], "label_unavailable")
          return
        end
        collected.rows.fetch(adapter.wire_kind) << row
        origin = origin(record["source"], adapter.wire_kind)
        # A recorded origin carries the source attribution, so `source` is omitted only without one.
        fields = record.keys - adapter.wire_schema.fetch("properties").keys - ["schema_version"]
        fields -= ["source"] if origin
        fields += part_maps(request.registry.record_kinds.fetch(record_kind), record)
        collected.omissions << omission(record_kind, id, fields.sort, "fields_not_in_wire_schema") unless fields.empty?
        if origin
          (collected.origins[adapter.wire_kind] ||= {})[id] = origin
        elsif record["source"].is_a?(Hash) && record["source"]["kind"] == "library"
          collected.omissions << omission(record_kind, id, ["record_origins"], "origin_identity_unavailable")
        end
      end

      # Each declared part path, as "devices[].user_data", where a member holds a map the row leaves out.
      def part_maps(kind, record)
        return [] unless kind.respond_to?(:parts)

        kind.parts.filter_map do |part|
          held = part.members(record).any? { |member| member["user_data"].is_a?(Hash) && !member["user_data"].empty? }
          "#{part.path}.user_data" if held
        end
      end

      # Every local record a written row names through its kind's dependencies, written too, and theirs in turn.
      def add_dependencies(request, declarations, collected)
        adapter_of = ->(kind) { declarations.find { |row| row.adapter.wire_kind == kind } }
        queue = collected.rows.flat_map { |kind, rows| rows.map { |row| [kind, row] } }
        until queue.empty?
          kind, row = queue.shift
          adapter = adapter_of.call(kind).adapter
          Dependencies.targets(adapter, mapped_values(adapter, row)).each do |target|
            written = (collected.rows[target.fetch("kind")] ||= [])
            next if written.any? { |item| item.fetch("id") == target.fetch("id") }

            declaration = adapter_of.call(target.fetch("kind"))
            count = written.length
            collect(request, declaration, declaration.record_kind, target.fetch("id"), collected)
            queue << [target.fetch("kind"), written.last] if written.length > count
          end
        end
      end

      def selection(request)
        params = request.params
        scope = params.fetch("scope", "all")
        selected = params.fetch("records", [])
        if (scope == "selected" && selected.empty?) || (scope == "all" && !selected.empty?)
          raise Error.new("params.invalid", "Selected scope needs local records; all scope takes no selection.")
        end

        available = request.registry.library_kinds.values.map { |row| row.adapter.wire_kind }
        kinds = params.fetch("kinds", available)
        raise Error.new("params.invalid", "Each export kind may be selected only once.") unless kinds.uniq == kinds
        unless (kinds - available).empty?
          raise Error.new("library.kind_unavailable", "An export kind has no installed library adapter.")
        end

        Selection.new(:scope => scope, :records => selected, :kinds => kinds)
      end

      def targets(request, scope, selected)
        if scope == "selected"
          pairs = selected.map { |row| [row.fetch("record_kind"), row.fetch("id")] }
          raise Error.new("params.invalid", "Each local record may be selected only once.") unless pairs.uniq == pairs

          pairs.each do |kind, id|
            unless request.registry.record_kinds.key?(kind)
              raise Error.new("target.not_found", "A selected local record kind is unavailable.")
            end

            read_record(request, kind, id)
          end
          return pairs.sort
        end
        request.registry.record_kinds.keys.sort.flat_map do |kind|
          request.engine.ids(kind).sort.map { |id| [kind, id] }
        end
      end

      def read_record(request, kind, id)
        request.engine.find(kind, id)
      rescue CodedError => error
        raise Error.new(error.code, "A local definition could not be read for library export."), :cause => nil
      end

      def reverse(adapter, record)
        # Even the reverse callback receives no arbitrary metadata or source snapshot.
        input = DeepCopy.call(record.slice(*adapter.mapped_schema.fetch("properties").keys, "id"))
        # Capture normalized authored semantics before either callback can mutate its detached input.
        baseline = mapped_values(adapter, input)
        row = adapter.reverse.call(DeepCopy.call(input))
        valid = JsonValue.problems(row).empty? && JsonSchema.validate(row, adapter.wire_schema).empty? &&
                row.is_a?(Hash) && row.fetch("id", nil) == record.fetch("id") &&
                (row.keys - adapter.wire_schema.fetch("properties").keys).empty?
        raise Error.new("library.adapter_invalid", "The adapter returned invalid library export values.") unless valid

        unless mapped_values(adapter, row) == baseline
          raise Error.new("library.adapter_invalid", "The reverse adapter changed authored library export values.")
        end

        DeepCopy.call(row)
      rescue CodedError
        raise Error.new("library.adapter_invalid", "The adapter could not produce valid library export values."),
              :cause => nil
      end

      def mapped_values(adapter, row)
        mapped = adapter.map.call(DeepCopy.call(row))
        unless JsonValue.problems(mapped).empty? && JsonSchema.validate(mapped, adapter.mapped_schema).empty?
          raise Error.new("library.adapter_invalid", "The adapter returned invalid mapped export values.")
        end

        DeepCopy.call(mapped)
      end

      def origin(source, wire_kind)
        return nil unless source.is_a?(Hash) && source["kind"] == "library" && source["record_kind"] == wire_kind

        keys = %w[provider_kind library_id record_id]
        return nil unless keys.all? { |key| safe_identity?(source[key]) }
        return nil unless Registry::ID_PATTERN.match?(source.fetch("provider_kind"))

        source.slice(*keys).merge("label" => source.fetch("provider_kind"))
      end

      def safe_identity?(value)
        value.is_a?(String) && /\A[a-zA-Z0-9_.-]{1,200}\z/.match?(value)
      end

      def omission(kind, id, fields, reason)
        result = { "record_kind" => kind, "fields" => fields, "reason" => reason }
        result["id"] = id if safe_identity?(id)
        result
      end

      # Counts and omissions, each labelled with its registered record kind's label for display.
      def summary(projection, registry)
        wire = registry.library_kinds.values.to_h { |row| [row.adapter.wire_kind, row.record_kind] }
        label = ->(record_kind) { registry.record_kinds.fetch(record_kind).label }
        kinds = projection.fetch("kinds").map do |kind, rows|
          { "kind" => kind, "record_kind_label" => label.call(wire.fetch(kind)), "count" => rows.length }
        end
        omissions = projection.fetch("omissions").map do |row|
          DeepCopy.call(row).merge("record_kind_label" => label.call(row.fetch("record_kind")))
        end
        { "kinds" => kinds, "omissions" => omissions }
      end
      private_class_method :selection, :collect, :targets, :read_record, :reverse, :mapped_values, :origin,
                           :safe_identity?, :omission, :part_maps, :add_dependencies
    end
  end
end
