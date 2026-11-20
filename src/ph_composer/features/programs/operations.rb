# frozen_string_literal: true

module PhComposer
  module Programs
    # Program, Schedule and Equipment Set persistence. Each operation takes its inputs as arguments, so a library
    # callback calls the same operation its action does. Every write reads through Store, so a write that
    # touches an unwritten default writes its bundle first, in the same proposal and Undo step.
    module Operations
      LABELS = { PROGRAM_KIND => "Program", SCHEDULE_KIND => "Schedule", EQUIPMENT_SET_KIND => "Equipment Set" }.freeze
      DEFAULTS = { PROGRAM_KIND => Program.method(:defaults), SCHEDULE_KIND => Schedule.method(:defaults),
                   EQUIPMENT_SET_KIND => EquipmentSet.method(:defaults) }.freeze
      DEFAULT_IN_USE = "programs.default_in_use"

      module_function

      # ---------------------------------------------------------------- create, edit, duplicate

      # A new record; with no name, the first free "<Label> N".
      def create(request, proposal, kind, values:, user_data: nil)
        values = DeepCopy.call(values)
        values["name"] = free_name(request, kind) if values.fetch("name", "").strip.empty?
        values = DEFAULTS.fetch(kind).call(values)
        unique!(request, kind, values.fetch("name"))
        Store.materialize_references!(request, proposal, kind, values)
        check_slots!(request, proposal, values) if kind == PROGRAM_KIND
        { "id" => request.engine.propose_create(kind, proposal, :values => values, :user_data => user_data) }
      end

      # A guarded edit of named values; nil removes an optional one. On a Schedule a new type swaps the form.
      def update(request, proposal, kind, id:, values:, expected_values:)
        before = Store.find(request, kind, id, :proposal => proposal)
        values = DeepCopy.call(values)
        values["name"] = values["name"].strip if values["name"]
        if kind == SCHEDULE_KIND
          values = Schedule.changes(before, values)
          keep_type_in_use!(request, before, values)
        end
        edit(request, proposal, kind, before, values, expected_values)
        { "id" => id }
      end

      # A Schedule a Program names keeps its type: its loads read that type (Program::SLOTS).
      def keep_type_in_use!(request, before, values)
        return if (values["type"] || before.fetch("type")) == before.fetch("type")

        user = Store.all(request, PROGRAM_KIND).first.find do |program|
          Store::KINDS.fetch(PROGRAM_KIND).referenced_targets(program).include?([SCHEDULE_KIND, before.fetch("id")])
        end
        return unless user

        raise CodedError.new("validation.failed", "Schedule #{before.fetch('name')} is used by Program " \
                                                  "#{user.fetch('name')}, so it keeps its type.")
      end

      # One edit of `before`, stored or unwritten: guarded by `expected_values`, unique by name, every Schedule a
      # Program names of the right type.
      def edit(request, proposal, kind, before, values, expected_values)
        id = before.fetch("id")
        changed = expected_values.keys.reject { |key| before[key] == expected_values[key] }
        unless changed.empty?
          raise CodedError.new("target.changed", "#{LABELS.fetch(kind)} #{id} has changed since it was read " \
                                                 "(#{changed.join(', ')}).", "fields" => changed)
        end

        unique!(request, kind, values["name"], :except => id) if values["name"]
        after = DeepCopy.call(before)
        values.each { |key, value| value.nil? ? after.delete(key) : after[key] = DeepCopy.call(value) }
        if Store.unwritten_record?(request, kind, id, :proposal => proposal)
          Store.materialize!(request, proposal, [[kind, id]] + Store::KINDS.fetch(kind).referenced_targets(after),
                             id => after)
        else
          Store.materialize_references!(request, proposal, kind, after)
          request.engine.propose_update(kind, id, proposal, :values => values)
        end
        check_slots!(request, proposal, after) if kind == PROGRAM_KIND
      rescue StandardError => error
        proposal.refuse(error)
        raise
      end

      # A copy with a "(copy)" name and a derived source. A Program's Schedules stay shared; an Equipment Set's
      # devices take new ids, each keeping its own user_data.
      def duplicate(request, proposal, kind, id:, name: nil)
        rows = Store.names(request, kind)
        source = Store.find(request, kind, id, :proposal => proposal)
        identity = Records::Identity.allocator(request, "id" => id, "name" => name)
        copy = lambda do |values|
          values["name"] = (name || Records::Names.copy_name(values.fetch("name"), rows)).strip
          Records::Names.unique!(values["name"], rows)
          values["source"] = { "kind" => "derived" }
          values["devices"] &&= values["devices"].map { |row| row.merge("id" => identity.call("dev")) }
          values
        end
        if Store.unwritten_record?(request, kind, id, :proposal => proposal)
          Store.materialize!(request, proposal, [[kind, id]])
          values = copy.call(Store::KINDS.fetch(kind).values(DeepCopy.call(source)))
          return { "id" => request.engine.propose_create(kind, proposal, :values => values) }
        end

        mapping = request.engine.propose_duplicate(kind, [id], proposal) { |values| copy.call(values) }
        { "id" => mapping.fetch(id) }
      end

      # ---------------------------------------------------------------- delete

      # Without a replacement, any remaining use refuses: the Model's default as programs.default_in_use, any other
      # as reference.in_use. With one, every use takes the replacement first, in the same Undo step.
      def delete(request, proposal, kind, id:, expected_values: {}, replacement_id: nil)
        if replacement_id == id
          raise CodedError.new("params.invalid", "Choose a different replacement #{LABELS.fetch(kind)}.")
        end

        before = Store.find(request, kind, id, :proposal => proposal)
        guard!(kind, before, expected_values)
        replacement = replacement_id && Store.find(request, kind, replacement_id, :proposal => proposal)
        # An unwritten record's own branch writes its bundle, a replacement from that bundle with it.
        if replacement && !Store.unwritten_record?(request, kind, id, :proposal => proposal)
          Store.materialize!(request, proposal, [[kind, replacement_id]])
        end
        result = kind == SCHEDULE_KIND ? delete_schedule(request, proposal, before, replacement) :
                                         delete_default_kind(request, proposal, kind, before, replacement)
        { "id" => id }.merge(result)
      rescue StandardError => error
        proposal.refuse(error)
        raise
      end

      def delete_default_kind(request, proposal, kind, before, replacement)
        id = before.fetch("id")
        if Settings.default_id(request.model, kind) == id && replacement.nil?
          raise CodedError.new(DEFAULT_IN_USE, "#{LABELS.fetch(kind)} #{before.fetch('name')} is the Model's " \
                                               "default; name a replacement to delete it.", "id" => id)
        end
        # An unwritten default leaves no record to delete: the default moves, and its bundle is no longer read.
        if Store.unwritten_record?(request, kind, id, :proposal => proposal)
          Settings.propose(request, proposal, Settings.kind_field(kind) => replacement.fetch("id"))
          return Records::Metadata.removed_user_data(Store::KINDS.fetch(kind), [])
        end

        plan = replacement && request.retarget_references(kind, :from => id, :to => replacement.fetch("id"))
        request.engine.propose_delete(kind, id, proposal, :reference_plan => plan)
      end

      def delete_schedule(request, proposal, before, replacement)
        id = before.fetch("id")
        if replacement && replacement.fetch("type") != before.fetch("type")
          raise CodedError.new("validation.failed", "The replacement Schedule must be #{before.fetch('type')}, as " \
                                                    "the one it replaces.")
        end
        if Store.unwritten_record?(request, SCHEDULE_KIND, id, :proposal => proposal)
          program = DefaultProgram::PROGRAM
          unless replacement
            raise CodedError.new("reference.in_use", "#{PROGRAM_KIND} #{program.fetch('id')} still refers to " \
                                                     "#{SCHEDULE_KIND} #{id}.", "target_kind" => SCHEDULE_KIND,
                                                                                "id" => id)
          end

          remapped = remap_schedules(program, id, replacement.fetch("id"))
          Store.materialize!(request, proposal, [[SCHEDULE_KIND, id]], id => nil, program.fetch("id") => remapped)
          return Records::Metadata.removed_user_data(Schedule::KIND, [])
        end

        if replacement
          engine = request.engine
          DefinitionLists.read(engine, PROGRAM_KIND, engine.ids(PROGRAM_KIND).sort).first.each do |program|
            after = remap_schedules(program, id, replacement.fetch("id"))
            next if after == program

            changed = Program::NAMES.reject { |name| after[name] == program[name] }
            request.engine.propose_update(PROGRAM_KIND, program.fetch("id"), proposal,
                                          :values => after.slice(*changed), :expected_values => program.slice(*changed))
          end
        end
        request.engine.propose_delete(SCHEDULE_KIND, id, proposal)
      end

      # `program` with every Schedule reference to `from` pointing at `to`.
      def remap_schedules(program, from, to)
        Program::REFERENCES.reduce(DeepCopy.call(program)) { |value, reference| reference.remap(value, from => to) }
      end

      # ---------------------------------------------------------------- defaults

      # Rewrites the residential default Program or the default Equipment Set from its definition, writing it if
      # the Model holds none, and writes back any default Schedule the Program names that the Model no longer
      # holds. Edited Schedules stay as they are: other Programs may share them, so a default Schedule given another
      # type refuses the reset. Another record holding the default's name refuses it too. `user_data` is kept;
      # a device the definition does not hold goes, and its map is reported.
      def reset_default(request, proposal, kind, expected_values: {})
        frozen = Store::BUNDLES.fetch(kind).first.last
        id = frozen.fetch("id")
        if Store.unwritten_record?(request, kind, id, :proposal => proposal)
          guard!(kind, frozen, expected_values)
          Store.materialize!(request, proposal, [[kind, id]])
          return { "id" => id }.merge(Records::Metadata.discard_report([]))
        end

        unique!(request, kind, frozen.fetch("name"), :except => id)
        restore_missing_schedules(request, proposal, frozen) if kind == PROGRAM_KIND
        values = Store::KINDS.fetch(kind).values(DeepCopy.call(frozen))
        removed = []
        if Store.stored?(request.engine, kind, id)
          before = request.engine.find(kind, id)
          guard!(kind, before, expected_values)
          removed = dropped_device_maps(before, frozen)
          request.engine.propose_update(kind, id, proposal, :values => values)
        else
          # Deleted after another record became the default: written back under its reserved id.
          proposal.put(kind, :before => nil, :after => DeepCopy.call(frozen))
          Store.check_references!(request, proposal, kind, frozen)
        end
        check_slots!(request, proposal, frozen) if kind == PROGRAM_KIND
        { "id" => id }.merge(Records::Metadata.discard_report(removed))
      rescue StandardError => error
        proposal.refuse(error)
        raise
      end

      # [address, map] of each device in `before` that `after` does not hold, whose map is not empty.
      def dropped_device_maps(before, after)
        kept = after.fetch("devices", []).map { |row| row.fetch("id") }
        before.fetch("devices", []).filter_map do |device|
          map = device["user_data"]
          next if kept.include?(device.fetch("id")) || !map.is_a?(Hash) || map.empty?

          [{ "id" => before.fetch("id"), "part_ids" => [device.fetch("id")] }, map]
        end
      end

      def restore_missing_schedules(request, proposal, program)
        Store::KINDS.fetch(PROGRAM_KIND).referenced_targets(program).map(&:last).uniq.each do |schedule_id|
          next if Store.stored?(request.engine, SCHEDULE_KIND, schedule_id) || proposal.find(SCHEDULE_KIND, schedule_id)

          record = DefaultProgram::SCHEDULES.find { |row| row.fetch("id") == schedule_id }
          proposal.put(SCHEDULE_KIND, :before => nil, :after => DeepCopy.call(record))
        end
      end

      # Sets the Model's default Program, Equipment Set or both. `expected_values` guards only the fields given.
      # Making another record the default writes the residential one first, so it stays in the Model.
      def update_settings(request, proposal, values:, expected_values:)
        raise CodedError.new("params.invalid", "Name a default to change.") if values.empty?

        current = Settings.read(request.model)
        changed = expected_values.keys.reject { |key| current[key] == expected_values[key] }
        unless changed.empty?
          raise CodedError.new("target.changed", "The Programs defaults changed since they were read. Nothing was " \
                                                 "written.", "fields" => changed)
        end

        values.each do |key, id|
          kind = Settings::FIELDS.fetch(key).first
          Store.find(request, kind, id, :proposal => proposal)
          next if id == current.fetch(key)

          Store.materialize!(request, proposal, [[kind, current.fetch(key)]])
        end
        Settings.propose(request, proposal, values)
        Settings.read(request.model).merge(values)
      rescue StandardError => error
        proposal.refuse(error)
        raise
      end

      # ---------------------------------------------------------------- devices

      def add_device(request, proposal, set_id:, type:, values:)
        before = Store.find(request, EQUIPMENT_SET_KIND, set_id, :proposal => proposal)
        if values.key?("id") || values.key?("type")
          raise CodedError.new("params.invalid", "A new device takes its id and type from the action.")
        end

        id = Records::Identity.allocator(request, "set_id" => set_id, "type" => type, "values" => values).call("dev")
        device = EquipmentTypes.device(type, id, values)
        edit(request, proposal, EQUIPMENT_SET_KIND, before, { "devices" => before.fetch("devices") + [device] }, {})
        { "id" => set_id, "device_id" => id }
      end

      # Edits one device's values; its type and id are fixed. nil removes a value, which its type may need.
      def update_device(request, proposal, set_id:, device_id:, values:, expected_values:)
        before = Store.find(request, EQUIPMENT_SET_KIND, set_id, :proposal => proposal)
        if values.key?("id") || values.key?("type")
          raise CodedError.new("params.invalid", "A device's id and type are fixed; add a new device for another type.")
        end

        missing_device!(set_id, device_id) unless device?(before, device_id)
        devices = before.fetch("devices").map do |device|
          next device unless device.fetch("id") == device_id

          guard_device!(set_id, device, expected_values)
          after = DeepCopy.call(device)
          values.each { |key, value| value.nil? ? after.delete(key) : after[key] = value }
          after
        end
        edit(request, proposal, EQUIPMENT_SET_KIND, before, { "devices" => devices }, {})
        { "id" => set_id, "device_id" => device_id }
      end

      def delete_device(request, proposal, set_id:, device_id:, expected_values: {})
        before = Store.find(request, EQUIPMENT_SET_KIND, set_id, :proposal => proposal)
        device = before.fetch("devices").find { |row| row.fetch("id") == device_id }
        missing_device!(set_id, device_id) unless device
        guard_device!(set_id, device, expected_values)
        devices = before.fetch("devices").reject { |row| row.fetch("id") == device_id }
        edit(request, proposal, EQUIPMENT_SET_KIND, before, { "devices" => devices }, {})
        map = device["user_data"]
        removed = map.is_a?(Hash) && !map.empty? ? [[{ "id" => set_id, "part_ids" => [device_id] }, map]] : []
        { "id" => set_id, "device_id" => device_id }.merge(Records::Metadata.discard_report(removed))
      end

      # ---------------------------------------------------------------- checks

      def device?(set, device_id)
        set.fetch("devices").any? { |row| row.fetch("id") == device_id }
      end

      def missing_device!(set_id, device_id)
        raise CodedError.new("target.not_found", "Equipment Set #{set_id} has no device #{device_id}.")
      end

      def guard_device!(set_id, device, expected_values)
        changed = expected_values.keys.reject { |key| device[key] == expected_values[key] }
        return if changed.empty?

        raise CodedError.new("target.changed", "Device #{device.fetch('id')} of Equipment Set #{set_id} has changed " \
                                               "since it was read (#{changed.join(', ')}).", "fields" => changed)
      end

      def guard!(kind, record, expected_values)
        changed = expected_values.keys.reject { |key| record[key] == expected_values[key] }
        return if changed.empty?

        raise CodedError.new("target.changed", "#{LABELS.fetch(kind)} #{record.fetch('id')} has changed since it " \
                                               "was read (#{changed.join(', ')}).", "fields" => changed)
      end

      # Every Schedule a Program names is of the type its load reads.
      def check_slots!(request, proposal, program)
        Program::SLOTS.each do |key, type|
          section, field = key.split(".")
          id = program.fetch(section)[field]
          next if id.nil?

          schedule = Store.find(request, SCHEDULE_KIND, id, :proposal => proposal)
          next if schedule.fetch("type") == type

          raise CodedError.new("validation.failed", "#{key} must name a #{type} Schedule; #{schedule.fetch('name')} " \
                                                    "is #{schedule.fetch('type')}.", "field" => key)
        end
      end

      def unique!(request, kind, name, except: nil)
        Records::Names.unique!(name, Store.names(request, kind), :except => except)
      end

      def free_name(request, kind)
        taken = Store.names(request, kind).map { |row| row.fetch("name").strip.downcase }
        label = LABELS.fetch(kind)
        (1..).each do |index|
          candidate = "#{label} #{index}"
          return candidate unless taken.include?(candidate.downcase)
        end
      end
    end
  end
end
