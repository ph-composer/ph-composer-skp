# frozen_string_literal: true

module PhComposer
  module Zones
    module Options
      module Adoption
        module_function

        def needs_adoption?(engine, record)
          return true if record.fetch("schema_version") == 1

          origin = Options.settings(engine)&.fetch("source_model_id")
          return true if origin != record.dig("choice_evidence", "source_model_id")

          Options.resolve(engine, record)
          false
        rescue CodedError
          true
        end

        def source(record, collection)
          field = collection == "building_segment" ? "building_segment" : "level"
          if record.fetch("schema_version") == 1
            name = record[field]
            return nil if name.nil?

            portable = { "id" => Records::Identity.derived(collection == "level" ? "lvl" : "bsg", "name" => name),
                         "schema_version" => 1, "name" => name, "colour" => "#1F7478" }
            portable["export_identifier"] = Options.export_identifier(name) if collection == "building_segment"
            key = "legacy:#{collection}:#{CanonicalJson.digest(name)}"
          else
            portable = record.fetch("choice_evidence")[field]
            return nil unless portable

            key = "copied:#{collection}:#{CanonicalJson.digest([record.dig('choice_evidence', 'source_model_id'),
                                                                portable])}"
          end
          { "key" => key, "collection" => collection, "name" => portable.fetch("name"),
            "colour" => portable.fetch("colour"), "export_identifier" => portable["export_identifier"],
            "source_id" => record.fetch("schema_version") == 1 ? nil : portable.fetch("id"),
            "portable" => portable, "origin" => record.dig("choice_evidence", "source_model_id") }
        end

        def sources(request, inventory)
          found = {}
          inventory.each do |row|
            record = row.fetch(:record)
            next unless needs_adoption?(request.engine, record)

            %w[building_segment level].each do |collection|
              entry = source(record, collection)
              next unless entry

              key = entry.fetch("key")
              found[key] ||= entry.merge("live" => 0, "recoverable" => 0, "members" => [])
              if row.fetch(:zone)
                found[key]["live"] += 1
              else
                found[key]["members"] << record.fetch("zone_id")
              end
            end
          end
          live_ids = inventory.select { |row| row.fetch(:zone) }.map { |row| row.fetch(:record).fetch("id") }
          found.each_value { |entry| entry["recoverable"] = (entry.fetch("members").uniq - live_ids).length }
          found.values.sort_by { |entry| [entry.fetch("collection"), entry.fetch("name"), entry.fetch("key")] }
        end

        # What adoption would ask the user: each source, and the sources whose names collide within one
        # collection, as lists of keys.
        def preview(request, inventory)
          entries = sources(request, inventory)
          shown = entries.map { |entry| entry.reject { |key, _| %w[portable members origin].include?(key) } }
          clusters = entries.group_by { |entry| [entry.fetch("collection"), Options.name_key(entry.fetch("name"))] }
                            .values.select { |cluster| cluster.length > 1 }
          { "required" => !entries.empty?, "sources" => shown,
            "suggested_segment" => Occurrences.default_segment(request.model),
            "collision_clusters" => clusters.map { |cluster| cluster.map { |entry| entry.fetch("key") } } }
        end

        def apply(request, proposal, mappings:)
          inventory = Inventory.rows(request.model)
          entries = sources(request, inventory)
          expected = entries.map { |entry| entry.fetch("key") }
          supplied = mappings.map { |mapping| mapping.fetch("source") }
          unless supplied.sort == expected.sort && supplied.uniq.length == supplied.length
            Options.refuse("target.changed", "Adoption choices no longer match the Model; reopen the preview")
          end
          return { "created_ids" => {}, "replacement_ids" => {} } if entries.empty?

          mapping = allocate_targets(request, proposal, entries, mappings)
          copy_option_extensions(request, proposal, entries, mappings, mapping)
          KINDS.each do |collection, kind|
            Options.validate_collection!(Options.records(request.engine, kind.id, proposal), collection)
          end
          current_default = Options.settings(request.engine)&.fetch("default_segment_id")
          first_segment = entries.find { |entry| entry.fetch("collection") == "building_segment" }
          default_id = current_default || mapping.fetch(first_segment.fetch("key"))
          Options.set_settings(request, proposal, default_id) unless default_id == current_default
          writes = []
          final_records = []
          inventory.each do |row|
            before = row.fetch(:record)
            next unless needs_adoption?(request.engine, before)

            after = DeepCopy.call(before)
            after["schema_version"] = 2
            %w[building_segment level].each do |collection|
              entry = source(before, collection)
              after["#{collection}_id"] = entry && mapping.fetch(entry.fetch("key"))
              after.delete(collection)
            end
            after["choice_evidence"] = Options.evidence(request.engine, after, proposal)
            Schema.validate!(after) if row.fetch(:zone)
            unless row.fetch(:zone) || Schema.stamp?(after)
              Options.refuse("validation.failed", "Invalid converted membership stamp")
            end
            final_records << [row, after]
            Options.add_rewrite(row, after, writes)
          end
          check_membership!(inventory, final_records)
          Options.add_writes(proposal, writes)
          { "created_ids" => mapping, "replacement_ids" => {} }
        end

        def allocate_targets(request, proposal, entries, mappings)
          mapping = {}
          roots = mappings.to_h { |choice| [choice.fetch("source"), choice] }
          entries_by_key = entries.to_h { |entry| [entry.fetch("key"), entry] }
          resolve_target = lambda do |key, visiting|
            return mapping.fetch(key) if mapping.key?(key)

            Options.refuse("params.invalid", "Adoption merge choices form a cycle") if visiting.include?(key)
            choice = roots.fetch(key)
            entry = entries_by_key.fetch(key)
            collection = entry.fetch("collection")
            target_source = choice["target_source"]
            if target_source
              survivor = entries_by_key[target_source]
              unless survivor && survivor.fetch("collection") == collection && choice["target_id"].nil?
                Options.refuse("reference.invalid", "Choose a source from the same option collection")
              end
              target = resolve_target.call(target_source, visiting + [key])
            elsif choice["target_id"]
              target = choice.fetch("target_id")
              request.engine.find(KINDS.fetch(collection).id, target, :change_set => proposal.record_changes)
            else
              target = Options.create_choice(request, proposal, collection, choice.fetch("name"),
                                             choice.fetch("colour"), :portable => entry.fetch("portable"))
            end
            mapping[key] = target
          end
          mappings.each { |choice| resolve_target.call(choice.fetch("source"), []) }
          mapping
        end

        def copy_option_extensions(request, proposal, entries, choices, mapping)
          by_origin = {}
          entries.each do |entry|
            choice = choices.find { |candidate| candidate.fetch("source") == entry.fetch("key") }
            next if choice["target_source"] || choice["target_id"] ||
                    entry.fetch("portable").fetch("extension_data", {}).empty?

            sources_by_kind = entries.select { |candidate| candidate["origin"] == entry["origin"] }
                                     .group_by { |candidate| KINDS.fetch(candidate.fetch("collection")).id }
            typed = by_origin[entry["origin"]] ||= sources_by_kind.to_h do |kind, sources|
              pairs = sources.group_by { |source| source.fetch("portable").fetch("id") }
              assignments = pairs.to_h do |source_id, definitions|
                targets = definitions.map { |definition| mapping.fetch(definition.fetch("key")) }.uniq
                unless targets.length == 1
                  Options.refuse("zone.options_conflict", "Copied extension references have conflicting destinations")
                end
                [source_id, targets.first]
              end
              [kind, assignments]
            end
            kind = KINDS.fetch(entry.fetch("collection"))
            Options.copy_extensions(request, proposal, kind, entry.fetch("portable"),
                                    mapping.fetch(entry.fetch("key")), typed)
          end
        end

        def check_membership!(inventory, final_records)
          projected = inventory.map do |row|
            changed = final_records.find { |candidate, _| candidate.equal?(row) }
            record = changed ? changed.last : row.fetch(:record)
            [row, record]
          end
          projected.group_by { |row, record| record[row.fetch(:zone) ? "id" : "zone_id"] }.each_value do |members|
            pairs = members.map { |_, record| record.values_at("building_segment_id", "level_id") }.uniq
            next if pairs.length == 1

            Options.refuse("zone.options_conflict", "Zone and member stamps disagree; resolve recovery evidence first")
          end
        end
      end
    end
  end
end
