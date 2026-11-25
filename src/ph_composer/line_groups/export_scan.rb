# frozen_string_literal: true

module PhComposer
  module LineGroups
    # A line group feature's export: the assigned Edges read from the export snapshot instead of the live walk, and the
    # rows its preflight gives over the live Model, naming no feature. Each call takes the feature's Spec.
    module ExportScan
      module_function

      # Every assigned Edge the snapshot holds directly inside a line group occurrence, as a Scan::Edge, and each one's
      # user_data by path. `zone_paths` are the Zone occurrence paths the Zones section lists, which say which groups a
      # Zone holds (`in_zone`). An Edge is `shared` when a ComponentInstance holds it or the snapshot reaches it at two
      # paths, as a pasted group does: the live walk reads that from the Group's definition, which the snapshot does not
      # keep. A record that cannot be read refuses the export, as the schedule's unreadable rows block it; an Edge
      # outside every line group is not read, as the live walk does not read it.
      #
      # The section calling this is the source of a claim another contributor makes on a group or an Edge, so each read
      # passes its occurrence path and the claimed payload is captured for its claimant. `fields` are the Edge record's
      # fields the read passes.
      def edges(spec, reader, zone_paths:, fields:)
        snapshot = reader.snapshot
        groups = groups(spec, reader, zone_paths)
        assigned = snapshot.entries.filter_map do |entry|
          next unless entry.kind == "edge" && groups.key?(entry.path[0...-1])

          record = entry.record(spec.edge_store.dictionary)
          [entry, record] if record
        end
        reached = assigned.map { |entry, _record| entry.path.last }.tally
        storage = snapshot.entries.select { |entry| entry.kind == "component_instance" }
                          .to_h { |entry| [entry.path, true] }
        user_data = {}
        found = assigned.map do |entry, record|
          readable!(record, spec.edge_record_kind, spec.edge_noun)
          read = reader.entity_record(record, :fields => fields, :target_kind => spec.edge_kind, :user_data => true,
                                              :path => entry.path)
          user_data[entry.path] = read.fetch("user_data", {})
          geometry = entry.geometry
          Scan::Edge.new(:path => entry.path, :group => groups.fetch(entry.path[0...-1]), :record => record,
                         :points_m => geometry.points_m, :vertex_ids => geometry.vertex_ids,
                         :shared => reached.fetch(entry.path.last) > 1 ||
                                    (1...entry.path.length).any? { |length| storage.key?(entry.path[0, length]) })
        end
        [found, user_data]
      end

      # Each group occurrence by path, detached as the live walk detaches it (Scan.edges).
      def groups(spec, reader, zone_paths)
        reader.snapshot.records(spec.group_store.dictionary, :kind => "group").to_h do |entry, record|
          readable!(record, spec.group_record_kind, spec.label)
          reader.entity_record(record, :fields => [spec.link_key], :target_kind => spec.group_kind, :path => entry.path)
          [entry.path, { "group_id" => record.fetch("id"), "group_path" => entry.path, "name" => entry.native_name,
                         spec.link_key => record[spec.link_key],
                         "in_zone" => zone_paths.any? { |path| inside?(path, entry.path) } }]
        end
      end

      def readable!(record, kind, noun)
        problem = kind.problems(record).first
        return unless problem

        raise PhComposer::Export::Blocked.new("record.unreadable", "A #{noun} record cannot be read: #{problem}.")
      end

      def inside?(parent, path)
        path.length > parent.length && path[0, parent.length] == parent
      end

      # The live walk's unreadable rows (Scan.edges) as blocking findings. An Edge is read only inside a readable group,
      # so a row whose parent is one is an Edge, which runs.locate selects; any other is a group. `groups` are the
      # walk's readable occurrences.
      def unreadable_findings(spec, unreadable, groups)
        group_paths = groups.map(&:path)
        unreadable.map do |row|
          path = row.fetch("path")
          edge = group_paths.include?(path[0...-1])
          { "code" => row.fetch("code"), "object_id" => nil, "blocks_export" => true,
            "message" => "A #{edge ? spec.edge_noun : spec.label} record cannot be read: #{row.fetch('message')}",
            "locate" => edge ? { "edge_paths" => [path] } : nil }
        end
      end

      # A finding as a preflight row of `section`. A finding whose `locate` holds runs.locate's params locates through
      # `locate`, that view command's name; any other takes the Locate the block gives it, or none.
      def preflight_row(section, locate, finding)
        row = { "code" => finding.fetch("code"), "section" => section, "object_id" => finding.fetch("object_id"),
                "message" => finding.fetch("message"), "blocks_export" => finding.fetch("blocks_export") }
        if (params = finding["locate"])
          row.merge("locate" => { "name" => locate, "params" => params })
        elsif block_given? && (other = yield(finding))
          row.merge("locate" => other)
        else
          row
        end
      end

      # The metadata problems the export refuses or notes, read as `edges` reads them: each type, only when there are
      # Edges (`types`), and each group, whose user_data are left out; and each Edge, whose user_data ride. `groups` are
      # the live walk's readable occurrences.
      def metadata_findings(spec, request, section, groups, types:)
        check = PhComposer::Export::MetadataCheck
        assigned = groups.flat_map(&:edges).uniq.filter_map { |edge| LineGroups.read(edge, spec.edge_store).first }
        (types ? check.findings(request, check.definitions(request, spec.type_kind), :section => section) : []) +
          check.findings(request, groups.map(&:record), :section => section, :target_kind => spec.group_kind) +
          check.findings(request, assigned, :section => section, :target_kind => spec.edge_kind, :user_data => true)
      end
      private_class_method :groups, :readable!, :inside?
    end
  end
end
