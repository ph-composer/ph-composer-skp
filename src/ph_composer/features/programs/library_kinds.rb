# frozen_string_literal: true

module PhComposer
  module Programs
    # The `programs`, `schedules` and `equipment_sets` library kinds (docs/LIBRARY_FILE_FORMAT.md), through the
    # neutral library coordinator as Materials and Frames are. A wire row holds the record's authored values only:
    # no id of its own beyond the row's, no source, user_data or extension payloads. A Program's wire row names
    # each Schedule by its record id in the same library, and declares them as its dependencies, so a copy brings
    # its Schedules (context/CONTRACTS.md, "Library dependencies"); its local copy names the local Schedules. An
    # Equipment Set's wire devices carry no ids: a copy allocates them. Every callback calls the operation the
    # matching Programs action calls.
    module LibraryKinds
      module_function

      def install(feature)
        [ScheduleLibrary.new, ProgramLibrary.new, EquipmentSetLibrary.new].each do |adapter|
          feature.library_kind("#{FEATURE_ID}.library_#{adapter.collection}", :contract_version => 1,
                                                                              :record_kind => adapter.kind.id,
                                                                              :adapter => adapter.declaration)
        end
      end
    end

    # What the three kinds share: the wire shape built from the kind's library field forms, the common fields'
    # defaults, canonical numbers, the fingerprint over every mapped field, and the local read, create and replace
    # callbacks over Operations.
    class LibraryKind
      attr_reader :collection, :kind, :fields

      def initialize(collection, kind, library_forms = {})
        @collection = collection
        @kind = kind
        properties = kind.values_schema.fetch("properties").reject { |key, _| key == "source" }
        @properties = properties.merge(DeepCopy.call(library_forms))
        @fields = @properties.keys
      end

      # The mapped values: every field, its library form where it has one.
      def schema
        SchemaShapes.object(DeepCopy.call(@properties), :optional => @fields - required)
      end

      def wire_schema
        shape = schema
        shape["properties"]["id"] = { "type" => "string", "minLength" => 1 }
        shape["required"] = %w[id] + wire_required
        shape
      end

      def required
        @fields
      end

      def wire_required
        ["name"]
      end

      def map(row)
        values = numbers(semantic(DeepCopy.call(row)), schema)
        problems = JsonSchema.validate(values, schema) + semantic_problems(values)
        unless problems.empty?
          raise CodedError.new("library.row_semantic_invalid", "The library row violates the #{kind.label} value " \
                                                               "contract: #{problems.first}")
        end

        values
      end

      def reverse(record)
        map(record).merge("id" => record.fetch("id"))
      end

      def fingerprint(values)
        normalized = map(values)
        CanonicalJson.digest(@fields.map { |key| [key, normalized[key]] })
      end

      def declaration
        PhComposer::Declarations::LibraryAdapter.new(
          :wire_kind => collection, :wire_version => 1, :fingerprint_version => 1, :wire_schema => wire_schema,
          :mapped_schema => schema, :fingerprint_fields => @fields, :map => method(:map), :reverse => method(:reverse),
          :fingerprint => method(:fingerprint), :display_label => ->(mapped) { mapped.fetch("name") },
          :local_read => local_read, :create => create, :replace => replace, :assign => assign,
          :dependencies => dependencies
        )
      end

      def dependencies
        nil
      end

      def assign
        nil
      end

      def callback(params, result, refuses:, examples: nil, &handler)
        PhComposer::Declarations::LibraryCallback.new(:params => params, :result => result, :refuses => refuses,
                                                      :handler => handler, :examples => examples)
      end

      # Every record a read sees, PH-Composer's unwritten defaults with them (Store).
      def local_read
        row = Shapes.object({ "id" => Shapes::TEXT, "mapped" => schema, "expected_values" => Shapes::OBJECT,
                              "source" => kind.values_schema.fetch("properties").fetch("source") },
                            :optional => ["source"])
        callback(Shapes::NONE, Shapes.list(row),
                 :refuses => %w[record.unreadable library.row_semantic_invalid]) do |request, _proposal|
          records, unreadable = Store.all(request, kind.id)
          unless unreadable.empty?
            raise CodedError.new("record.unreadable", "A #{kind.label} cannot be read, so the copy cannot be " \
                                                      "resolved against it.")
          end

          records.map do |record|
            projection = { "id" => record.fetch("id"), "mapped" => map(record),
                           "expected_values" => DeepCopy.call(record.slice(*@fields)) }
            projection["source"] = DeepCopy.call(record["source"]) if record.key?("source")
            projection
          end
        end
      end

      def create
        params = Shapes.create(kind)
        params.fetch("properties").fetch("values")["properties"] = create_values
        callback(params, Shapes::RESULT, :refuses => Refuses::CREATE) do |request, proposal|
          Operations.create(request, proposal, kind.id, :values => created(request, request.params.fetch("values")),
                                                        :user_data => request.params["user_data"])
        end
      end

      def create_values
        kind.values_schema.fetch("properties")
      end

      def created(_request, values)
        values
      end

      def replace
        callback(Shapes.update(kind), Shapes::RESULT, :refuses => Refuses::EDIT) do |request, proposal|
          params = request.params
          Operations.update(request, proposal, kind.id, :id => params.fetch("id"), :values => params.fetch("values"),
                                                        :expected_values => params.fetch("expected_values"))
        end
      end

      private

      # The row's own values with the common fields' defaults: no notes, no links, the name trimmed.
      def semantic(row)
        values = { "notes" => "", "datasheet_links" => [] }.merge(row.slice(*@fields))
        values["name"] = values.fetch("name", "").strip
        values
      end

      def semantic_problems(values)
        Fields.problems(values)
      end

      # `value` with each integer in a number field written as a float, so equal values fingerprint alike.
      def numbers(value, schema)
        case value
        when Hash
          properties = schema.is_a?(Hash) ? schema.fetch("properties", {}) : {}
          value.to_h { |key, item| [key, numbers(item, properties[key])] }
        when Array then value.map { |item| numbers(item, schema.is_a?(Hash) ? schema["items"] : nil) }
        when Integer
          number = schema.is_a?(Hash) && Array(schema["type"]).include?("number")
          number ? value.to_f : value
        else value
        end
      end
    end

    # A Schedule's wire row is its type and PH form; missing form values take the type's defaults.
    class ScheduleLibrary < LibraryKind
      def initialize
        super("schedules", Schedule::KIND)
      end

      def required
        %w[name notes datasheet_links type days_per_week weeks_per_year]
      end

      def wire_required
        %w[name type]
      end

      private

      def semantic(row)
        defaults = Schedule.defaults(row.slice(*@fields).merge("name" => row.fetch("name", "")))
        super(defaults.slice(*@fields))
      end

      def semantic_problems(values)
        Schedule.problems(values)
      end
    end

    # A Program's wire row holds any of its eight loads, each with any of its values; the rest take a new
    # Program's. Its Schedules are its dependencies, by record id in the same library.
    class ProgramLibrary < LibraryKind
      def initialize
        super("programs", Program::KIND, Program::LIBRARY_SECTIONS)
      end

      # The Schedules the Program names, once each, by the id each slot holds.
      def schedules(mapped)
        Program::SLOTS.keys.filter_map do |key|
          section, field = key.split(".")
          id = mapped.fetch(section)[field]
          id && { "kind" => "schedules", "id" => id }
        end.uniq
      end

      def remap(mapped, ids)
        table = ids.fetch("schedules", {})
        Program::SLOTS.each_key do |key|
          section, field = key.split(".")
          id = mapped.fetch(section)[field]
          mapped.fetch(section)[field] = table.fetch(id) if table.key?(id)
        end
        mapped
      end

      def dependencies
        PhComposer::Declarations::LibraryDependencies.new(:kinds => ["schedules"], :list => method(:schedules),
                                                          :remap => method(:remap))
      end

      def assign
        ModelDefaultAssignment.callback(kind)
      end

      private

      def semantic(row)
        values = super
        Program::NAMES.each do |name|
          given = row[name].is_a?(Hash) ? row[name] : {}
          values[name] = DeepCopy.call(Program::EMPTY.fetch(name)).merge(given)
        end
        values
      end

      def semantic_problems(values)
        Program.problems(values)
      end
    end

    # An Equipment Set's wire devices carry their type and any of its fields, the type's defaults filling the
    # rest; a copy allocates each device's id. A replacement keeps the id and user_data of each local device whose
    # place in the list the incoming device of the same type takes, and refuses to drop a device holding user_data.
    class EquipmentSetLibrary < LibraryKind
      PLACEHOLDER = "dev_000000000000"

      def initialize
        super("equipment_sets", EquipmentSet::KIND,
              "devices" => { "type" => "array", "items" => EquipmentSet::LIBRARY_DEVICE })
      end

      def assign
        ModelDefaultAssignment.callback(kind)
      end

      def create_values
        super.merge("devices" => { "type" => "array", "items" => EquipmentSet::LIBRARY_DEVICE })
      end

      def created(request, values)
        identity = Records::Identity.allocator(request, "library_equipment_set" => values)
        values.merge("devices" => values.fetch("devices", []).map { |row| row.merge("id" => identity.call("dev")) })
      end

      def replace
        params = Shapes.update(kind)
        params.fetch("properties").fetch("values")["properties"] =
          params.dig("properties", "values", "properties").merge("devices" => create_values.fetch("devices"))
        callback(params, Shapes::RESULT, :refuses => Refuses::EDIT) do |request, proposal|
          id = request.params.fetch("id")
          before = Store.find(request, kind.id, id, :proposal => proposal)
          values = request.params.fetch("values")
          values = values.merge("devices" => replaced(request, before, values.fetch("devices"))) if values["devices"]
          Operations.edit(request, proposal, kind.id, before, values, request.params.fetch("expected_values"))
          { "id" => id }
        end
      end

      private

      def replaced(request, before, devices)
        locals = before.fetch("devices")
        identity = Records::Identity.allocator(request, "library_replacement" => [before.fetch("id"), devices])
        result = devices.each_with_index.map do |device, index|
          local = locals[index]
          next device.merge("id" => identity.call("dev")) unless local && local.fetch("type") == device.fetch("type")

          device.merge(local.slice("id", "user_data"))
        end
        kept = result.map { |device| device.fetch("id") }
        dropped = locals.find { |device| !kept.include?(device.fetch("id")) && !device.fetch("user_data", {}).empty? }
        if dropped
          raise CodedError.new("validation.failed", "Replacing #{before.fetch('name')} would drop device " \
                                                    "#{dropped.fetch('display_name')} and its user_data. Clear it, " \
                                                    "or copy the library Equipment Set as a new one.",
                               "device_id" => dropped.fetch("id"))
        end

        result
      end

      def semantic(row)
        values = super
        values["devices"] = Array(row["devices"]).map do |device|
          given = device.reject { |key, _| %w[id type user_data].include?(key) }
          EquipmentTypes.device(device.fetch("type"), PLACEHOLDER, given).reject { |key, _| key == "id" }
        end
        values
      end

      def semantic_problems(values)
        super + values.fetch("devices").flat_map { |device| EquipmentTypes.problems(device.merge("id" => PLACEHOLDER)) }
      end
    end

    # A copied Program or Equipment Set made the Model's default, guarded by the defaults as last read, through
    # the operation ph_composer.programs.settings.update calls.
    module ModelDefaultAssignment
      TARGET = SchemaShapes.object({
        "mode" => { "type" => "string", "enum" => ["model_default"] },
        "expected_settings" => SchemaShapes.described(
          Shapes::OBJECT, "The defaults as ph_composer.programs.settings.get last read them; those given are " \
                          "checked. {} skips the check."
        )
      }, :description => "model_default makes the copy the Model's default of its kind.")

      module_function

      def callback(kind)
        field = Settings.kind_field(kind.id)
        reserved = Settings::FIELDS.fetch(field).last
        example = { "target" => { "mode" => "model_default", "expected_settings" => { field => reserved } },
                    "local_id" => "#{kind.id_prefix}_Ab12Cd34Ef56" }
        PhComposer::Declarations::LibraryCallback.new(
          :params => SchemaShapes.object({ "target" => TARGET, "local_id" => Shapes::TEXT }),
          :result => Shapes::RESULT, :refuses => Refuses::EDIT, :examples => [example],
          :handler => lambda do |request, proposal|
            local_id = request.params.fetch("local_id")
            Operations.update_settings(request, proposal, :values => { field => local_id },
                                                          :expected_values => request.params.dig("target",
                                                                                                 "expected_settings"))
            { "id" => local_id }
          end
        )
      end
    end
  end
end
