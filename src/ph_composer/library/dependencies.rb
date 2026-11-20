# frozen_string_literal: true

module PhComposer
  module Library
    # The records a library row names in other kinds, as a Program names its Schedules (context/CONTRACTS.md,
    # "Library dependencies"). A kind declares them on its adapter (Declarations::LibraryDependencies): a row names
    # each by its wire record id in the same library, and its local copy names the local record instead. Here
    # are the checked reads of that declaration; the Coordinator copies the records themselves.
    module Dependencies
      module_function

      # [{ "kind", "id" }] the row's mapped values name, each once, checked against the declaration.
      def targets(adapter, mapped)
        declared = adapter.dependencies
        return [] unless declared

        list = declared.list.call(DeepCopy.call(mapped))
        valid = list.is_a?(Array) && list.all? do |target|
          target.is_a?(Hash) && target.keys.sort == %w[id kind] && declared.kinds.include?(target["kind"]) &&
            target["id"].is_a?(String) && !target["id"].empty?
        end
        raise Error.new("library.adapter_invalid", "The kind adapter returned invalid dependencies.") unless valid

        DeepCopy.call(list.uniq)
      end

      # `mapped` with each record `ids` maps (`{ kind => { record_id => local_id } }`) named by its local id,
      # still inside the kind's mapped schema.
      def remap(adapter, mapped, ids)
        return mapped if ids.empty?

        value = adapter.dependencies.remap.call(DeepCopy.call(mapped), DeepCopy.call(ids))
        unless JsonValue.problems(value).empty? && JsonSchema.validate(value, adapter.mapped_schema).empty?
          raise Error.new("library.adapter_invalid", "The kind adapter remapped its dependencies to invalid values.")
        end

        DeepCopy.call(value)
      end

      # The incoming values as a local copy would hold them, for comparing with local records: each dependency
      # already copied from the same source (`source`, the row's identity) named by that local record, the
      # others by their record ids. Reads only local records, so it needs no dependency catalog; `locals` keeps
      # each kind's local read for the next row of the same page.
      def in_local_terms(request, source, adapter, mapped, locals = {})
        targets = targets(adapter, mapped)
        return mapped if targets.empty?

        ids = {}
        targets.group_by { |target| target.fetch("kind") }.each do |kind, rows|
          locals[kind] ||= begin
            declaration = State.kind(kind, request.registry)
            CallbackInvoker.call(request, declaration, declaration.adapter.local_read, {}, :readonly => true)
          end
          rows.each do |target|
            identity = source.merge("record_kind" => kind, "record_id" => target.fetch("id"))
            found = locals.fetch(kind).select { |row| Resolver.same_source?(row["source"], identity) }
            (ids[kind] ||= {})[target.fetch("id")] = found.first.fetch("id") if found.length == 1
          end
        end
        remap(adapter, mapped, ids)
      end

      # How one copy reports a dependency it copied or reused.
      def report(target, local_id, outcome)
        { "kind" => target.fetch("kind"), "record_id" => target.fetch("id"), "local_id" => local_id,
          "outcome" => outcome }
      end
    end
  end
end
