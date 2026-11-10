# frozen_string_literal: true

module PhComposer
  module Export
    # The metadata rules extraction applies to every record it reads (RecordReader), as plain checks a
    # preflight can run without collecting geometry or translating (context/CONTRACTS.md, "Records and
    # extension data"). Extraction raises the first problem a record has; a preflight reports them all as
    # blocking rows with the same codes and messages. Nothing here changes or sanitizes a record. What only
    # the translation can check (the HBJSON conformance and the passed user_data guard) runs later, in the
    # export task.
    module MetadataCheck
      # One problem: the code and message extraction would raise.
      Problem = Struct.new(:code, :message, keyword_init: true)

      module_function

      # Every problem `stored` (a record's stored hash, with its `id`) has when extraction reads it. Metadata
      # of the wrong shape is the record's own validation finding, not one of these.
      # `user_data` is whether the contributor passes its user_data through; `target_kind`, for an entity
      # record, finds the extension envelopes another contributor claims (Collection.claims); `named` maps a
      # namespace a definition read names to the payload fields it exports.
      def problems(stored, catalog:, claims:, reserved:, user_data: false, target_kind: nil, named: {})
        id = stored.fetch("id")
        found = user_data ? reserved_problems(id, stored.fetch("user_data", {}), reserved) : []
        extensions = stored.fetch("extension_data", {})
        (extensions.is_a?(Hash) ? extensions : {}).each do |namespace, envelope|
          claimed = target_kind && claims[[namespace, target_kind]]
          problem = if claimed || named.key?(namespace)
                      payload_problem(id, namespace, envelope, catalog)
                    else
                      left_out_problem(id, namespace, envelope)
                    end
          found << problem if problem
        end
        found
      end

      # The passed user_data's first reserved top-level key, as a problem, or nil: what extraction raises.
      def reserved_problem(id, value, reserved)
        reserved_problems(id, value, reserved).first
      end

      # One problem per reserved top-level key the passed user_data takes, for a preflight to list them all.
      def reserved_problems(id, value, reserved)
        taken = value.is_a?(Hash) ? value.keys & reserved : []
        taken.map do |key|
          Problem.new(:code => "export.blocked",
                      :message => "#{id} has user_data under the reserved key #{key}, which an exporter writes " \
                                  "itself. Rename that key. Nothing was written.")
        end
      end

      # An envelope a contributor exports must be understood by an installed extension.
      def payload_problem(id, namespace, envelope, catalog)
        status = Records::Extension.status(envelope, catalog.extension(namespace))
        return nil if status == "understood"

        code = { "unavailable" => "extension.unavailable", "invalid" => "extension.invalid" }
               .fetch(status, "extension.schema_unsupported")
        Problem.new(:code => code,
                    :message => "#{namespace} data on #{id} is #{status}, so it cannot be exported. Nothing was " \
                                "written.")
      end

      # An envelope no contributor exports is left out only when it declares itself local_only.
      def left_out_problem(id, namespace, envelope)
        relevance = Records::Extension.readable?(envelope) ? envelope.fetch("export_relevance", "unknown") : "unknown"
        case relevance
        when "local_only" then nil
        when "required"
          Problem.new(:code => "extension.unavailable",
                      :message => "#{id} holds #{namespace} data that export needs, and nothing installed exports " \
                                  "it. Nothing was written.")
        else
          Problem.new(:code => "export.relevance_unknown",
                      :message => "#{id} holds #{namespace} data whose effect on the export is unknown. Nothing " \
                                  "was written.")
        end
      end

      # Blocking preflight rows for every problem in `records` (stored hashes, each with its `id`), read as
      # `section`'s contract reads them, each distinct problem once however many placements show the record.
      def findings(request, records, section:, user_data: false, target_kind: nil)
        registry = request.registry
        reserved = (Collection.reserved(registry) + [RecordReader::RESERVED_USER_DATA_KEY]).uniq
        rules = { :catalog => registry.catalog, :claims => Collection.claims(registry), :reserved => reserved,
                  :user_data => user_data, :target_kind => target_kind }
        rows = records.select { |record| record.is_a?(Hash) && record["id"].is_a?(String) }.flat_map do |record|
          problems(record, **rules).map do |problem|
            { "code" => problem.code, "section" => section, "object_id" => record.fetch("id"),
              "message" => problem.message, "blocks_export" => true }
          end
        end
        rows.uniq { |row| row.values_at("object_id", "code", "message") }
      end

      # The stored records of one definition kind that can be read; one that cannot is the owner's own
      # preflight finding already.
      def definitions(request, kind_id)
        request.engine.ids(kind_id).sort.filter_map do |id|
          request.engine.find(kind_id, id)
        rescue CodedError
          nil
        end
      end

      # The readable records `store` keeps on entities extraction reads (GeometrySnapshot.walk), through Groups
      # and component contents, each entity once however many placements show it: a Face or Edge inside a
      # cutting component is not captured, so its record is not read. An unreadable record is the owner's own
      # preflight finding already.
      def entity_records(model, store)
        found = []
        seen = {}
        pending = [[model.entities, true]]
        until pending.empty?
          entities, captured = pending.shift
          entities.each do |entity|
            geometry = entity.is_a?(Sketchup::Face) || entity.is_a?(Sketchup::Edge)
            next if seen[[entity.object_id, captured]] || (geometry && !captured)

            seen[[entity.object_id, captured]] = true
            record = readable(store, entity)
            found << record if record
            contents = OccurrencePath.contents(entity)
            pending << [contents, captured && !cuts?(entity)] if contents
          end
        end
        found.uniq(&:object_id)
      end

      def cuts?(entity)
        entity.is_a?(Sketchup::ComponentInstance) && entity.definition.behavior.cuts_opening?
      end

      def readable(store, entity)
        return nil unless store.marks?(entity)

        record = store.read(entity)
        record.is_a?(Hash) ? record : nil
      rescue CodedError, TypeError
        nil
      end
      private_class_method :readable, :cuts?
    end
  end
end
