# frozen_string_literal: true

module PhComposer
  module Zones
    module Faces
      # Zones owns the join. Assembly values and effective colour come only from the registered read;
      # entity writes remain detached Face steps inside the caller's proposal.
      module AssemblyAssignment
        KIND = "ph_composer.assemblies.assembly"
        READ = "ph_composer.assemblies.assemblies.all"
        # Each Face field an Assembly hints at, and the Assembly value that hints it.
        HINTS = { "face_type" => "type", "boundary_condition" => "exterior_condition" }.freeze
        # The finding a Face field raises when it differs from its Assembly's hint.
        MISMATCH_CODES = { "face_type" => "face.assembly_type_mismatch",
                           "boundary_condition" => "face.assembly_exterior_condition_mismatch" }.freeze

        module_function

        def catalog(request)
          request.memo(:assembly_catalog) do
            result = request.query(READ)
            { :records => result.fetch("records").to_h { |row| [row.fetch("id"), row] },
              :unreadable => result.fetch("unreadable").map { |row| row.fetch("id") } }
          end
        end

        def resolve(request, id)
          valid = request.memo(:assembly_validated) { {} }
          unless valid[id]
            request.engine.resolve_reference(KIND, id)
            valid[id] = true
          end
          catalog(request).fetch(:records).fetch(id)
        end

        def fill_hints(request, record, intent)
          return unless intent.dig("assembly_id", "mode") == "set"

          hints = resolve(request, record.fetch("assembly_id")).fetch("values")
          HINTS.each do |field, hint|
            mode = intent.dig(field, "mode")
            next unless record[field].nil? && (mode.nil? || mode == "keep")
            next if hints[hint].nil?

            record[field] = hints.fetch(hint)
          end
        end

        # The glossary's words for both sides, never honeybee's stored strings.
        def mismatch(field, face, assembly)
          if field == "face_type"
            labels = ColourModes::FACE_TYPE_LABELS
            "This Face's type is #{labels.fetch(face, face)}; its Assembly's type is " \
              "#{labels.fetch(assembly, assembly)}."
          else
            labels = ColourModes::BOUNDARY_LABELS
            "This Face's Boundary condition is #{labels.fetch(face, face)}; its Assembly's is " \
              "#{labels.fetch(assembly, assembly)}."
          end
        end

        def state(request, record)
          id = record && record["assembly_id"]
          return "absent" if id.nil?

          rows = catalog(request)
          return "resolved" if rows.fetch(:records).key?(id)

          rows.fetch(:unreadable).include?(id) ? "invalid" : "dangling"
        end

        def findings(request, occurrence, record, index)
          return [] unless record

          assembly = record["assembly_id"] && catalog(request).fetch(:records)[record["assembly_id"]]
          found = []
          # The reversed side of a pair holds its Assembly from the other Zone: a Floor Assembly's
          # counterpart is a ceiling, so its hints describe the authored side, not this one.
          if assembly && !record["assembly_reversed"]
            HINTS.each do |field, hint|
              value = assembly.fetch("values")[hint]
              next if value.nil? || record[field].nil? || record[field] == value

              found << finding(MISMATCH_CODES.fetch(field), record, mismatch(field, record[field], value))
            end
          end
          if record["boundary_condition"] == "Surface" && record["adjacency"]
            other = Occurrences.resolve_face(request.model, record.fetch("adjacency").fetch("counterpart"),
                                             :index => index)
            unless pair_matches?(record, FACE_STORE.read(other.entity))
              found << finding("face.assembly_pair_mismatch", record, PAIR_MISMATCH)
            end
          end
          found
        rescue CodedError
          found || [] # Stale adjacency has its own state; a mismatch cannot safely infer its peer.
        end

        PAIR_MISMATCH = "The two sides of this interior Face need one Assembly, reversed on one side. " \
                        "Assign the Assembly again to one side."

        # A Surface pair is one interior element (context/CONTRACTS.md, "Interior pair Assembly"). Both
        # sides name no Assembly, or both name one Assembly and exactly one side holds it reversed.
        def pair_matches?(record, other)
          mine = record["assembly_id"]
          theirs = other && other["assembly_id"]
          return theirs.nil? if mine.nil?

          mine == theirs && !record["assembly_reversed"] != !other["assembly_reversed"]
        end

        # A Face the gesture names for its Assembly, or whose Assembly it changed, is its pair's authored
        # side. The counterpart takes the same Assembly reversed, or loses its Assembly when the authored
        # side's was cleared. `named` lists [reference, record] for every Face the gesture named, so naming
        # an unchanged Face still repairs its pair. When a gesture names both sides, the first is the
        # authored side. A pair whose adjacency is not current is left alone: export omits it.
        def mirror_pairs(request, updates, index, named: [])
          changed = updates.to_h { |row| [Occurrences.key(row.fetch("reference")), row] }
          # Gesture order first, so the first Face named is the authored side.
          rows = named.to_h do |reference, record|
            key = Occurrences.key(reference)
            [key, changed[key] || { "reference" => reference, "before" => record, "after" => record,
                                    "stamp" => nil, "change" => "updated" }]
          end
          changed.each { |key, row| rows[key] ||= row }
          named_keys = named.map { |reference, _record| Occurrences.key(reference) }
          settled = {}
          rows.each do |key, row|
            next if settled[key] || !(named_keys.include?(key) || assembly_changed?(row["before"], row["after"]))

            settled[key] = true
            other = counterpart(request, row, index)
            next unless other

            other_key = Occurrences.key(other.reference)
            next if settled[other_key]

            settled[other_key] = true
            existing = rows[other_key]
            base = existing ? existing.fetch("after") : FACE_STORE.read(other.entity)
            mirrored = mirror(base, row.fetch("after"))
            if existing
              existing["after"] = mirrored
              updates << existing unless updates.include?(existing) || existing["before"] == mirrored
            elsif mirrored != base
              updates << { "reference" => other.reference(base.fetch("id")), "before" => base, "after" => mirrored,
                           "stamp" => nil, "change" => "updated" }
            end
          end
          # A named side the mirror put back as it was writes nothing; a row with a stamp still writes that.
          updates.reject! { |row| row["before"] == row["after"] && row["stamp"].nil? }
          updates
        end

        # A pair Solve adjacencies just made holds one Assembly. When only one side names an Assembly,
        # or both name the same one, the side that held it (the first, when both did) is the authored side
        # and the other takes it reversed. Two different Assemblies stay, for the preflight to name.
        def settle_new_pair!(first, second)
          ids = [first["assembly_id"], second["assembly_id"]].compact.uniq
          return [first, second] unless ids.length == 1

          authored, other = first["assembly_id"] ? [first, second] : [second, first]
          authored.delete("assembly_reversed")
          other["assembly_id"] = ids.first
          other["assembly_reversed"] = true
          [Schema.validate!(first), Schema.validate!(second)]
        end

        def assembly_changed?(before, after)
          before.nil? || before["assembly_id"] != after["assembly_id"] ||
            before["assembly_reversed"] != after["assembly_reversed"]
        end

        # The writable counterpart occurrence of an update's Surface Face, or nil when it has none current.
        def counterpart(request, row, index)
          after = row.fetch("after")
          return nil unless after["boundary_condition"] == "Surface" && after["adjacency"]

          occurrence = Occurrences.resolve_face(request.model, row.fetch("reference"), :index => index)
          return nil unless Zones::Adjacency.state(request.model, occurrence, after, :index => index) == "current"

          reference = after.fetch("adjacency").fetch("counterpart")
          other = Occurrences.resolve_face(request.model, reference, :mutable => true, :index => index)
          Zones::Selection.resolve(request.model, other.zone.reference, index)
          other
        end

        def mirror(base, authored)
          result = DeepCopy.call(base)
          if authored["assembly_id"]
            result["assembly_id"] = authored.fetch("assembly_id")
            result["assembly_reversed"] = true
          else
            result.delete("assembly_id")
            result.delete("assembly_reversed")
          end
          Schema.validate!(result)
        end

        def finding(code, record, message)
          { "code" => code, "message" => message, "assembly_id" => record["assembly_id"] }
        end

        def usage(rows)
          rows.select { |row| row.dig("values", "assembly_id") }.group_by { |row| row.dig("values", "assembly_id") }
              .sort.map do |id, faces|
            { "assembly_id" => id, "face_count" => faces.length,
              "gross_area_m2" => faces.sum { |row| row.fetch("area_m2") },
              "faces" => faces.map { |row| row.fetch("reference") } }
          end
        end

        # A nil `assembly_id` clears the Assembly of every target.
        def assign(request, proposal, assembly_id:, targets:)
          id = assembly_id
          resolve(request, id) if id
          unique = targets.group_by { |target| Occurrences.key(target.fetch("reference")) }
          if unique.values.any? { |group| group.uniq.length > 1 }
            raise CodedError.new("params.invalid", "Repeated Face targets disagree on identity or expected values.")
          end

          Faces.check_limit!(unique.length)
          index = Zones::Index.new(request.model)
          named = []
          updates = unique.values.filter_map do |group|
            target = group.first
            occurrence, before = target_record(request, target.fetch("reference"), index)
            Faces.check_expected!(before, target.fetch("expected_values"))
            named << [occurrence.reference(before && before.fetch("id")), before] if before
            update(request, occurrence, before, id, :authored => true)
          end
          mirror_pairs(request, updates, index, :named => named)
          Faces.check_limit!(updates.length)
          propose(proposal, updates)
          { "face_ids" => updates.map { |row| row.fetch("after").fetch("id") } }
        end

        def target_record(request, reference, index)
          occurrence = Occurrences.resolve_face(request.model, reference,
                                                :mutable => true,
                                                :allow_unassigned => reference["entity_id"].nil?, :index => index)
          Zones::Selection.resolve(request.model, occurrence.zone.reference, index)
          before = FACE_STORE.read(occurrence.entity)
          Schema.validate!(before) if before
          [occurrence, before]
        end

        # `authored`: the gesture names this Face, so it becomes the authored side of its pair. A catalog
        # retarget is not authoring: each side keeps which side of the pair it holds.
        def update(request, occurrence, before, id, authored: false)
          return nil if before.nil? && id.nil?

          after = before ? DeepCopy.call(before) : Faces.new_record(request, occurrence)
          id.nil? ? after.delete("assembly_id") : after["assembly_id"] = id
          after.delete("assembly_reversed") if authored || id.nil?
          return nil if before == after

          Schema.validate!(after)
          { "reference" => occurrence.reference(before && before.fetch("id")),
            "before" => before, "after" => after, "stamp" => nil, "change" => before ? "updated" : "created" }
        end

        def propose(proposal, updates)
          return if updates.empty?

          scopes = updates.map { |row| row.fetch("reference").fetch("zone_path")[0...-1] }.uniq.map do |path|
            Operations::EntityScope.new(path)
          end
          proposal.add_step(ClassifyStep.new(:updates => updates), :scopes => scopes)
        end

        # Catalog replacement is not a pointer gesture: every reachable use moves, without the
        # gesture ceiling. Orphan/shared/locked uses refuse before any step or catalog write applies.
        def retarget(request, proposal, from:, to:)
          index = Zones::Index.new(request.model)
          reachable = index.all_faces.to_h do |face|
            record = FACE_STORE.read(face.entity)
            [face.zone.path + face.path, face.reference(record && record["id"])]
          end
          entries = ReferenceTargets.entries(request.model).select { |entry| entry.record["assembly_id"] == from }
          updates = []
          stranded = []
          entries.each do |entry|
            Schema.validate!(entry.record)
            reference = reachable[entry.key]
            unless reference
              stranded << { "id" => entry.record.fetch("id"), "path" => entry.key, "reason" => "outside_zone" }
              next
            end
            begin
              occurrence, before = target_record(request, reference, index)
              updates << update(request, occurrence, before, to)
            rescue CodedError => error
              stranded << { "id" => entry.record.fetch("id"), "path" => entry.key, "reason" => error.code }
            end
          end
          refuse_stranded(from, stranded) unless stranded.empty?
          updates.compact!
          propose(proposal, updates)
          Faces.reassignment_plan(updates)
        end

        def refuse_stranded(id, rows)
          routes = rows.map do |row|
            Faces::STRANDED_ROUTES.fetch(row.fetch("reason"), "resolve #{row.fetch('reason')}")
          end
          raise CodedError.new("reference.in_use",
                               "#{rows.length} Face(s) still use Assembly #{id} where replacement cannot reach them. " \
                               "For each, #{routes.uniq.join('; or ')}, then replace again.",
                               "target_kind" => KIND, "id" => id, "faces" => rows)
        end
      end
    end
  end
end
