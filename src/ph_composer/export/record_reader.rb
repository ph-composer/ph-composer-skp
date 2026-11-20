# frozen_string_literal: true

module PhComposer
  module Export
    # A contributor refuses to export the Model, or the Model holds data export cannot safely leave
    # out. The message says what to do; nothing is written.
    class Blocked < CodedError; end

    # How an export contributor reads records (context/CONTRACTS.md, "Records and extension data").
    # Only a kind's declared values and the extension fields the contributor names leave the Model:
    #
    # - `user_data` goes out only where the owner passes it through (`user_data: true`), as Honeybee
    #   carries it on the matching object; it is never interpreted, it may not use the reserved
    #   `ph_composer` key, and the export report counts what reached the HBJSON
    #   (HbjsonMetadata.passed). Elsewhere a record that has some gets a finding saying it was left out.
    #   A record part's map (Records::Part) follows the same rule: `records` takes it out of the values
    #   with a finding, unless the contributor reads the parts itself (`parts: true`) and passes each
    #   member through `entity_record`, which carries or omits its map.
    # - An extension envelope the contributor names must be understood, and only the named payload
    #   fields go out.
    # - On an entity or a catalog record, an envelope another contributor claims (`entity_projections:`) must be
    #   understood; its declared fields go to that contributor's projection store, keyed by occurrence, or by
    #   record for a catalog record.
    # - Any other envelope is left out when it declares itself `local_only`, and blocks the export when
    #   it is `required` or its relevance is unknown: nothing guesses from a payload's text.
    class RecordReader
      # `record_id` leaves as the wire's `object_id`; a member of that name would shadow Object#object_id.
      # A finding about a record part (Records::Part) also carries `reference`, the
      # `{"kind", "id", "part_ids"}` that ph_composer.records.update_metadata takes to write that part's map.
      Finding = Struct.new(:code, :section, :record_id, :message, :reference, keyword_init: true) do
        def to_h
          row = { "code" => code, "section" => section, "object_id" => record_id, "message" => message }
          reference ? row.merge("reference" => DeepCopy.call(reference)) : row
        end
      end

      RESERVED_USER_DATA_KEY = "ph_composer"

      attr_reader :findings

      # `claims` maps `[namespace, target_kind]` to the claim (Collection.claims): its contributor, fields and
      # source section.
      # `reserved` lists the user_data top-level keys a user may not take: PH-Composer's own and every
      # namespace an export contributor declares it writes (Privacy.user_data_keys).
      def initialize(engine, catalog, claims: {}, reserved: [RESERVED_USER_DATA_KEY])
        @engine = engine
        @catalog = catalog
        @claims = claims
        @reserved = (reserved + [RESERVED_USER_DATA_KEY]).uniq
        @projected = Hash.new { |hash, key| hash[key] = [] }
        @read = {}
        @findings = []
        @section = nil
      end

      # Runs the block as the reader for `section`, so findings name the section they arose in.
      def within(section)
        previous = @section
        @section = section
        yield
      ensure
        @section = previous
      end

      # Every record of `kind_id`, in id order, as `{"id" => id, <values>..., "extensions" => {...}}`.
      # `extensions` maps a namespace to the payload fields to include; `user_data: true` passes each
      # record's user_data through as `"user_data"`. `parts: true` leaves each part's map in the values
      # for the contributor to pass through `entity_record`; otherwise every part map is left out.
      def records(kind_id, extensions: {}, user_data: false, parts: false)
        @engine.ids(kind_id).sort.map do |id|
          record(kind_id, @engine.find(kind_id, id), extensions, user_data, parts)
        end
      end

      # Entity-owned feature records use the same metadata boundary. `fields` is an explicit
      # contributor allowlist; an omitted core field never leaves under an opaque value slot. An entity
      # read passes its `target_kind`, so a claimed envelope is validated rather than left out. Only the
      # claim's source section passes the occurrence `path` as well, once per occurrence: that read
      # captures the row for the claimant; a shared read without `path` validates and captures nothing.
      # A contributor reading a record part (`records(..., parts: true)`) passes the part's `part:`
      # reference, `{"kind", "id", "part_ids"}`, so a finding about its map names the record that holds it.
      def entity_record(stored, fields:, target_kind: nil, path: nil, user_data: false, part: nil)
        id = stored.fetch("id")
        passed = metadata(id, stored, user_data, part)
        stored.fetch("extension_data", {}).each do |namespace, envelope|
          claimed = target_kind && @claims[[namespace, target_kind]]
          next leave_out(id, namespace, envelope) unless claimed

          payload = declared_payload(id, namespace, envelope, claimed.fetch("fields"))
          capture_claimed(namespace, target_kind, claimed, id, path, payload) if path
        end
        { "id" => id }.merge(DeepCopy.call(stored.slice(*fields))).merge(passed)
      end

      # Captures the claimed envelopes of one entity occurrence for their claimants, without the
      # metadata findings `entity_record` already gave: for an owner whose section contract is not where
      # its shared reads ran. Call it only from that owner's section contract, once per occurrence.
      def capture_entity(stored, target_kind:, path:)
        stored.fetch("extension_data", {}).each do |namespace, envelope|
          claimed = @claims[[namespace, target_kind]]
          next unless claimed

          payload = declared_payload(stored.fetch("id"), namespace, envelope, claimed.fetch("fields"))
          capture_claimed(namespace, target_kind, claimed, stored.fetch("id"), path, payload)
        end
      end

      # Captures the claimed envelopes of one catalog record (a Building Segment) for their claimants. A catalog
      # record has no occurrence, so each row's `path` is null. Its owner reads the record through
      # `entity_record(..., target_kind:)` first, which checks its metadata, and calls this from the claim's
      # source section once for each record it exports.
      def capture_record(stored, target_kind:)
        capture_entity(stored, :target_kind => target_kind, :path => nil)
      end

      # The claimed rows for `namespace` on `target_kind`, in the order the owner's section read them.
      # Only the claimant reads them, after the owner's section ran (Collection orders by `requires:`).
      def entity_projection(namespace, target_kind, reader:)
        claim = @claims[[namespace, target_kind]]
        unless claim && claim.fetch("contributor") == reader
          raise InternalError, "#{reader.inspect} reads #{namespace} on #{target_kind} without claiming it."
        end

        rows = @projected[[namespace, target_kind]]
        @read[[namespace, target_kind]] = rows.length
        DeepCopy.call(rows)
      end

      # A non-blocking finding the reading section discloses about `id`: something it left out of its records,
      # or a warning about what it wrote. It joins the result's findings, and so the report.
      # A finding repeated by a second read of the same record, such as a Building-Segment two Zones name or
      # an Edge id a split left on two Edges, is listed once. A record's omitted map is one finding however
      # many sections read the record (a Material read for its constructions and for its sources); the first
      # section to read it names it.
      def note(code, id, message, reference: nil)
        finding = Finding.new(:code => code, :section => @section, :record_id => id, :message => message,
                              :reference => reference)
        @findings << finding unless @findings.any? { |kept| same_finding?(kept, finding) }
      end

      # A claimed row its claimant never read, including one captured after its read, would leave
      # declared data out of the export silently.
      def reconcile!
        unread = @projected.keys.find { |key| @projected[key].length > @read.fetch(key, 0) }
        return unless unread

        namespace, target_kind = unread
        raise Blocked.new("export.blocked",
                          "#{namespace} data on #{target_kind} is claimed for export but its exporter did not " \
                          "read it. Nothing was written.", "section" => @claims[unread].fetch("contributor"))
      end

      private

      # One occurrence's claimed payload, captured for its claimant.
      def capture_claimed(namespace, target_kind, claimed, id, path, payload)
        capture(namespace, target_kind, claimed, "id" => id, "path" => DeepCopy.call(path), "payload" => payload)
      end

      # The claim names the section that captures its rows; a capture anywhere else means the
      # declaration and the owner disagree, which no export may paper over.
      def capture(namespace, target_kind, claim, row)
        unless claim.fetch("source_section") == @section
          raise InternalError, "#{@section.inspect} captured #{namespace} on #{target_kind}, but its claim names " \
                               "#{claim.fetch('source_section').inspect}."
        end

        @projected[[namespace, target_kind]] << row
      end

      def record(kind_id, stored, extensions, user_data, parts)
        id = stored.fetch("id")
        passed = metadata(id, stored, user_data)
        exported = stored.fetch("extension_data", {}).each_with_object({}) do |(namespace, envelope), out|
          fields = extensions[namespace]
          if fields
            out[namespace] = declared_payload(id, namespace, envelope, fields)
          else
            leave_out(id, namespace, envelope)
          end
        end
        kind = @engine.kind(kind_id)
        values = DeepCopy.call(kind.values(stored))
        leave_out_parts(kind, id, values) unless parts
        { "id" => id }.merge(values).merge(exported.empty? ? {} : { "extensions" => exported }).merge(passed)
      end

      # Takes each part's map out of `values`, with a finding for one that is not empty.
      def leave_out_parts(kind, id, values)
        kind.parts.each do |part|
          part.addressed_members(values).each do |part_ids, member|
            map = member.delete("user_data")
            next if map.nil? || map.empty?

            omit_metadata(member.fetch("id"), { "kind" => kind.id, "id" => id, "part_ids" => part_ids })
          end
        end
      end

      # The rules are MetadataCheck's, which a preflight runs too; extraction raises the first problem.
      def declared_payload(id, namespace, envelope, fields)
        refuse(MetadataCheck.payload_problem(id, namespace, envelope, @catalog))
        DeepCopy.call(envelope.fetch("payload").slice(*fields))
      end

      def leave_out(id, namespace, envelope)
        refuse(MetadataCheck.left_out_problem(id, namespace, envelope))
        note("export.metadata_omitted", id, "#{namespace} data is local to this Model and was not exported.")
      end

      # `{"user_data" => ...}` to merge into the exported record, or `{}`. `part` is a part's reference.
      def metadata(id, stored, pass, part = nil)
        value = stored.fetch("user_data", {})
        return {} if value.empty?

        unless pass
          omit_metadata(id, part)
          return {}
        end

        refuse(MetadataCheck.reserved_problem(id, value, @reserved))
        { "user_data" => DeepCopy.call(value) }
      end

      # A part's finding names the record holding it and the part's id path, as the write takes them.
      def omit_metadata(id, part = nil)
        unless part
          return note("export.metadata_omitted", id, "User data is local to this Model and was not exported.")
        end

        note("export.metadata_omitted", id,
             "User data on part #{part.fetch('part_ids').join(' / ')} of #{part.fetch('kind')} #{part.fetch('id')} " \
             "is local to this Model and was not exported.", :reference => part)
      end

      def same_finding?(kept, finding)
        return kept == finding unless finding.code == "export.metadata_omitted"

        kept.to_h.reject { |key, _| key == "section" } == finding.to_h.reject { |key, _| key == "section" }
      end

      def refuse(problem)
        raise Blocked.new(problem.code, problem.message, "section" => @section) if problem
      end
    end
  end
end
