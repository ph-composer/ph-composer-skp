# frozen_string_literal: true

module PhComposer
  module Climate
    # The climate record's reads and writes. Each write takes its inputs as arguments, stages the whole record
    # with its rewritten provenance as one change, and is guarded by the editable fields the caller last read,
    # so a stale edit refuses and writes nothing. The record is staged whole rather than through
    # Engine#propose_update, which would drop a key set to null; a null here is a value not yet entered.
    module Operations
      KIND_ID = Schema::KIND_ID
      RECORD_ID = Schema::RECORD_ID
      NOT_FOUND = "climate.not_found"
      NO_ORIGINAL = "climate.no_original"
      NONE = { "state" => "none", "climate" => nil, "missing" => [], "edited_cells" => [], "limit_check" => nil }.freeze

      module_function

      # The stored climate record, or nil when the Model has none.
      def stored(engine)
        return nil unless engine.ids(KIND_ID).include?(RECORD_ID)

        engine.find(KIND_ID, RECORD_ID)
      end

      # climate.get: the record with its derived state, what is missing, the edited cells and the limit check
      # against the Model's site. State none and nulls when there is no climate. Reads never write. An edited
      # cell is its row and column alone: its value and the file's are in the values and their as_read copy,
      # and the provenance lists both, so a station with every value edited still fits one agent reply.
      def read(request)
        describe(stored(request.engine), Settings.site(request.model))
      end

      def describe(record, site)
        return NONE.merge("missing" => [], "edited_cells" => []) unless record

        values = Schema::KIND.values(record)
        missing = Completeness.missing(values)
        { "state" => missing.empty? ? "complete" : "incomplete",
          "climate" => { "id" => record.fetch("id"), "values" => values,
                         "user_data" => DeepCopy.call(record.fetch("user_data", {})) },
          "missing" => missing, "edited_cells" => Edits.cells(values).map { |cell| cell.slice("row", "column") },
          "limit_check" => LimitCheck.call(site, values) }
      end

      # The limit check the Model's climate gets at `site`, a stored or a proposed one; nil with no climate.
      def limit_check(engine, site)
        record = stored(engine)
        record && LimitCheck.call(site, Schema::KIND.values(record))
      end

      # The climate card of the sidebar summary.
      def card(engine, site)
        found = describe(stored(engine), site)
        values = found.dig("climate", "values")
        { "state" => found.fetch("state"), "origin" => values&.fetch("origin"),
          "verdict" => found.dig("limit_check", "verdict"), "edited" => !found.fetch("edited_cells").empty? }
      end

      # Enter Values by Hand: a new climate from the editable fields, with gaps allowed. A Model that already
      # holds a climate refuses, since the caller read none.
      def enter_values(request, proposal, values:)
        refusing(proposal) do
          unless stored(request.engine).nil?
            refuse("target.changed", "The Model already holds a climate; edit it with save_values")
          end

          after = { "id" => RECORD_ID, "schema_version" => Schema::KIND.schema_version }.merge(Record.hand(values))
          stage(request, proposal, nil, after)
        end
      end

      # Edit Values: the editable fields of the Model's climate. A station's name and coordinates come from its
      # file, so Edit Values refuses to change them; Replace does.
      def save_values(request, proposal, values:, expected_values:)
        refusing(proposal) do
          before = guarded(request, expected_values)
          if before.fetch("origin") == "station" &&
             values.slice(*Schema::STATION_IDENTITY) != before.slice(*Schema::STATION_IDENTITY)
            refuse("validation.failed", "A station's name and coordinates come from its file; replace the " \
                                        "station to change them")
          end

          stage(request, proposal, before, before.merge(Record.with_values(Schema::KIND.values(before), values)))
        end
      end

      # Restore Original Values: every value the file read, back over the edits.
      def restore_original(request, proposal, expected_values:)
        refusing(proposal) do
          before = guarded(request, expected_values)
          if before.fetch("as_read").nil?
            refuse(NO_ORIGINAL, "A climate entered by hand has no original values to restore")
          end

          stage(request, proposal, before, before.merge(Record.restored(Schema::KIND.values(before))))
        end
      end

      # Clear: deletes the climate. The site and the design temperatures are settings and stay. The result
      # reports the record's user_data, which the delete discards and Undo brings back.
      def clear(request, proposal, expected_values:)
        refusing(proposal) do
          guarded(request, expected_values)
          removed = request.engine.propose_delete(KIND_ID, RECORD_ID, proposal)
          written(nil, request).merge(removed)
        end
      end

      # Runs one write; a refusal it raises also refuses the proposal, so nothing staged before it can commit.
      def refusing(proposal)
        yield
      rescue StandardError => error
        proposal.refuse(error)
        raise
      end

      # The editable fields a caller reads and sends back as expected_values.
      def editable(record)
        record.slice(*Schema::EDITABLE)
      end

      # The Model's climate, guarded by the editable fields the caller last read. The guard is on values:
      # user_data has its own write route, ph_composer.records.update_metadata, and edits keep it as stored.
      def guarded(request, expected_values)
        record = stored(request.engine)
        refuse(NOT_FOUND, "The Model holds no climate") if record.nil?
        refuse("target.changed", "The climate changed since it was read") unless editable(record) == expected_values
        record
      end

      def stage(request, proposal, before, after)
        problems = Schema::KIND.problems(after)
        refuse("validation.failed", "The climate is not valid: #{problems.first}") unless problems.empty?

        proposal.put(KIND_ID, :before => before, :after => after)
        written(after, request)
      end

      # What a write answers: the climate's state as it will stand, without the record itself, which
      # climate.get reads back. A write's declared result stays small enough to describe in one reply.
      def written(record, request)
        describe(record, Settings.site(request.model)).reject { |key, _value| key == "climate" }
      end

      def refuse(code, message)
        raise CodedError.new(code, "#{message}. Nothing was written.")
      end
    end
  end
end
