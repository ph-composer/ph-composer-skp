# frozen_string_literal: true

module PhComposer
  module Programs
    # Where Programs, Schedules and Equipment Sets are read from: the stored records, and PH-Composer's defaults
    # while the Model holds none of them. Reads never write (context/CONTRACTS.md, "Programs, Schedules and
    # Equipment Sets").
    #
    # The default Program and its Schedules are one bundle, and the default Equipment Set another. A bundle is
    # unwritten while its default is the Model's (the settings field is null) and its record is not stored; reads
    # then answer its frozen records (DefaultProgram) under their reserved ids. The first write that touches an
    # unwritten bundle writes it whole (`materialize!`): an edit, duplicate or delete of one of its records, a
    # record that comes to refer to one of its Schedules, a device change, or a settings update that makes another
    # record the default, so the residential default stays in the Model as an ordinary record. From then on its
    # records are stored like any other and follow the ordinary engine rules.
    #
    # The generic record routes (ph_composer.records.*) read stored records only, so an unwritten default answers
    # target.not_found there until a Programs write stores it; reset_default stores it unchanged.
    module Store
      KINDS = { PROGRAM_KIND => Program::KIND, SCHEDULE_KIND => Schedule::KIND,
                EQUIPMENT_SET_KIND => EquipmentSet::KIND, DWELLING_KIND => Dwelling::KIND }.freeze
      BUNDLES = {
        PROGRAM_KIND => [[PROGRAM_KIND, DefaultProgram::PROGRAM]] +
                        DefaultProgram::SCHEDULES.map { |record| [SCHEDULE_KIND, record] },
        EQUIPMENT_SET_KIND => [[EQUIPMENT_SET_KIND, DefaultEquipmentSet::SET]]
      }.freeze

      module_function

      def stored?(engine, kind, id)
        engine.ids(kind).include?(id)
      end

      # Whether the bundle whose head is `bundle` (PROGRAM_KIND or EQUIPMENT_SET_KIND) is still unwritten: neither
      # stored nor staged in `proposal`, and the Model's default.
      def unwritten?(request, bundle, proposal: nil)
        id = head_id(bundle)
        bundle_unwritten?(Settings.stored(request.model), bundle,
                          stored?(request.engine, bundle, id) || !proposal&.find(bundle, id).nil?)
      end

      def head_id(bundle)
        BUNDLES.fetch(bundle).first.last.fetch("id")
      end

      # Pure: whether the bundle headed by `bundle` is unwritten, from the stored defaults (Settings.stored) and
      # whether its head record is stored.
      def bundle_unwritten?(stored_settings, bundle, head_stored)
        stored_settings.fetch(Settings.kind_field(bundle)).nil? && !head_stored
      end

      # Pure: the frozen records of `kind` that reads answer, from the stored defaults and `stored_ids`, the ids of
      # each kind's stored records. The export reads its snapshot this way.
      def frozen(stored_settings, kind, stored_ids)
        rows = BUNDLES.select do |bundle, _records|
          bundle_unwritten?(stored_settings, bundle, stored_ids.fetch(bundle, []).include?(head_id(bundle)))
        end.values.flatten(1)
        rows.select { |row_kind, _record| row_kind == kind }.map { |_kind, record| DeepCopy.call(record) }
      end

      # The bundle an unwritten frozen record of `kind` and `id` belongs to, or nil.
      def bundle_of(request, kind, id, proposal: nil)
        BUNDLES.each do |bundle, records|
          next unless records.any? { |record_kind, record| record_kind == kind && record.fetch("id") == id }

          return bundle if unwritten?(request, bundle, :proposal => proposal)
        end
        nil
      end

      # The frozen records of `kind` that reads answer, the Model holding none of their bundles.
      def unwritten(request, kind, proposal: nil)
        rows = BUNDLES.select { |bundle, _records| unwritten?(request, bundle, :proposal => proposal) }.values
        rows.flatten(1).select { |row_kind, _record| row_kind == kind }.map { |_kind, record| DeepCopy.call(record) }
      end

      # One record as a read sees it: stored, staged in `proposal`, or an unwritten default.
      def find(request, kind, id, proposal: nil)
        record = unwritten(request, kind, :proposal => proposal).find { |row| row.fetch("id") == id }
        record || request.engine.find(kind, id, :change_set => proposal)
      end

      # Whether `id` names an unwritten default of `kind`.
      def unwritten_record?(request, kind, id, proposal: nil)
        !bundle_of(request, kind, id, :proposal => proposal).nil?
      end

      # [records, unreadable] of `kind`: each stored record, or why it cannot be read, then every unwritten
      # default, in id order.
      def all(request, kind)
        records, unreadable = DefinitionLists.read(request.engine, kind, request.engine.ids(kind))
        [(records + unwritten(request, kind)).sort_by { |record| record.fetch("id") }, unreadable]
      end

      # The records of `kind` that names are unique among: every readable one.
      def names(request, kind)
        all(request, kind).first
      end

      # Writes every unwritten bundle a frozen record among `targets` ([[kind, id], ...]) belongs to. `changes`
      # maps a frozen record's id to the record it is written as instead, or to nil to leave it out. Each record is
      # validated and its references checked as the proposal leaves them. Returns the ids written.
      def materialize!(request, proposal, targets, changes = {})
        bundles = targets.filter_map { |kind, id| bundle_of(request, kind, id, :proposal => proposal) }.uniq
        rows = bundles.flat_map { |bundle| BUNDLES.fetch(bundle) }.filter_map do |kind, record|
          id = record.fetch("id")
          after = changes.key?(id) ? changes.fetch(id) : DeepCopy.call(record)
          after && [kind, after]
        end
        rows.each do |kind, record|
          problems = KINDS.fetch(kind).problems(record)
          unless problems.empty?
            raise CodedError.new("validation.failed", "#{KINDS.fetch(kind).label} #{record['id']} is not valid: " \
                                                      "#{problems.first}.", "findings" => problems)
          end

          proposal.put(kind, :before => nil, :after => record)
        end
        rows.each { |kind, record| check_references!(request, proposal, kind, record) }
        rows.map { |_kind, record| record.fetch("id") }
      rescue StandardError => error
        proposal.refuse(error)
        raise
      end

      def check_references!(request, proposal, kind, record)
        KINDS.fetch(kind).referenced_targets(record).each do |target_kind, id|
          request.engine.resolve_reference(target_kind, id, :change_set => proposal)
        end
      end

      # Writes every unwritten bundle `record`'s references reach, so a stored record never names an unwritten one.
      def materialize_references!(request, proposal, kind, record)
        materialize!(request, proposal, KINDS.fetch(kind).referenced_targets(record))
      end
    end
  end
end
