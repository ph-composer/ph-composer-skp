# frozen_string_literal: true

module PhComposer
  module Zones
    module Options
      module Registration
        OPTION = Shapes.object({ "id" => Shapes::ID, "name" => NAME, "colour" => COLOUR }).freeze
        MAP = { "type" => "object", "additionalProperties" => { "type" => %w[string null] } }.freeze
        RESULT = Shapes.object({ "created_ids" => MAP, "replacement_ids" => MAP }).freeze
        COLLECTION = { "type" => "string", "enum" => %w[building_segment level] }.freeze
        MANAGE = Shapes.object({
          "collection" => COLLECTION, "options" => Shapes.list(OPTION), "expected_options" => Shapes.list(OPTION),
          "default_segment_id" => { "type" => %w[string null] },
          "expected_default_segment_id" => { "type" => %w[string null] }, "replacements" => MAP
        }).freeze
        MAPPING = Shapes.object({ "source" => Shapes::ID, "target_id" => { "type" => %w[string null] },
                                  "name" => NAME, "colour" => COLOUR,
                                  "target_source" => { "type" => %w[string null] } },
                                :optional => ["target_source"]).freeze
        SOURCE = Shapes.object({ "key" => Shapes::ID, "collection" => COLLECTION, "name" => NAME,
                                 "colour" => COLOUR, "export_identifier" => { "type" => %w[string null] },
                                 "source_id" => { "type" => %w[string null] }, "live" => Shapes::COUNT,
                                 "recoverable" => Shapes::COUNT }).freeze
        ADOPTION = Shapes.object({ "required" => { "type" => "boolean" }, "sources" => Shapes.list(SOURCE),
                                   "suggested_segment" => { "type" => "string" },
                                   "collision_clusters" => Shapes.list(Shapes.list(Shapes::ID)) }).freeze
        REFUSALS = (Refuses::ZONE_TARGET + %w[reference.invalid reference.in_use copy.rule_missing extension.invalid
                                              zone.option_duplicate zone.option_export_conflict zone.options_conflict
                                              zone.options_adoption_required]).uniq.freeze

        module_function

        def install(feature)
          [SEGMENTS, LEVELS, SETTINGS].each { |kind| feature.record_kind(kind) }
          feature.reference_target(Records::ReferenceTarget.new(
            :id => STAMP_KIND, :label => "Zone membership stamp",
            :records => Inventory.method(:stamp_entries), :validate => Inventory.method(:stamp_problems),
            :references => CHOICE_REFERENCES
          ))
          feature.query("#{PREFIX}.all", :description => "Model-owned Segment/Level choices and adoption preview.",
                                         :response => { "bounded" => false, "prefer" => "#{PREFIX}.list" },
                                         :params => Shapes::NONE, :result => all_result, :refuses => REFUSALS,
                                         :examples => [{}]) { |request| Options.all(request) }
          feature.query("#{PREFIX}.adoption_preview", :description => "Read-only legacy/copied choice inventory.",
                                                      :params => Shapes::NONE, :result => ADOPTION,
                                                      :refuses => REFUSALS,
                                                      :examples => [{}]) do |request|
            Adoption.preview(request, Inventory.rows(request.model))
          end
          install_sources_page(feature)
          install_sources_detail(feature)
          install_actions(feature)
          feature.snapshot_section(PREFIX, :query => "#{PREFIX}.all")
          install_retargeters(feature)
        end

        SOURCES_LIST = "#{PREFIX}.adoption_sources.list"

        # adoption_preview's sources a bounded page at a time, by key, each naming the cluster it collides in.
        def install_sources_page(feature)
          row = SOURCE.merge("required" => SOURCE.fetch("required") + ["cluster"],
                             "properties" => SOURCE.fetch("properties").merge(
                               "truncated" => ContextChildren::TRUNCATED,
                               "cluster" => { "type" => %w[string null],
                                              "description" => "The key of the first source in this source's " \
                                                               "collision cluster (adoption_preview's " \
                                                               "collision_clusters), or null when it collides " \
                                                               "with none." }
                             ))
          feature.query(SOURCES_LIST,
                        :description => "One bounded page of the legacy and copied choices adoption_preview lists, " \
                                        "by key, beside whether adoption is required and the suggested Segment.",
                        :refuses => (REFUSALS + %w[query.cursor_expired query.limit_invalid]).uniq,
                        :params => Shapes.object({ "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR },
                                                 :optional => Pages::PAGE_KEYS),
                        :result => Shapes.object({ "required" => { "type" => "boolean" },
                                                   "suggested_segment" => { "type" => "string" },
                                                   "sources" => Shapes.list(row), "next_cursor" => Pages::NEXT_CURSOR,
                                                   "total" => Pages::TOTAL }),
                        :examples => [{}, { "limit" => 50 }]) { |request| sources_page(request) }
        end

        SOURCES_DETAIL = "#{PREFIX}.adoption_sources.detail"

        # One adoption source's row, whole, in fragments: a name longer than a list row keeps.
        def install_sources_detail(feature)
          feature.query(SOURCES_DETAIL,
                        :description => "One part of one adoption source as adoption_preview lists it, exactly, as " \
                                        "canonical JSON text in fragments: join every fragment's text in order, " \
                                        "check its sha256 and parse it.",
                        :refuses => (REFUSALS + %w[query.cursor_expired target.not_found]).uniq,
                        :params => Shapes.object({ "key" => Shapes.described(Shapes::ID, "The source's key."),
                                                   "path" => Fragments.path_param(SOURCE.fetch("properties").keys -
                                                                                  ["key"], "[\"name\"]"),
                                                   "cursor" => Pages::CURSOR }, :optional => ["cursor"]),
                        :result => Shapes.object({ "key" => Shapes::ID, "type" => Fragments::TYPE,
                                                   "fragment" => Fragments::FRAGMENT,
                                                   "next_cursor" => Pages::NEXT_CURSOR }),
                        :examples => [{ "key" => "legacy:level:0a1b", "path" => ["name"] }]) do |request|
            key = request.params.fetch("key")
            source = Adoption.preview(request, Inventory.rows(request.model)).fetch("sources")
                             .find { |row| row.fetch("key") == key }
            raise CodedError.new("target.not_found", "No adoption source is #{key}.") unless source

            { "key" => key }.merge(Fragments.detail(request, SOURCES_DETAIL, source, request.params.fetch("path"),
                                                    :parts => source.keys - ["key"]))
          end
        end

        def sources_page(request)
          Pages.limit(request.params)
          Pages.position(request, SOURCES_LIST)
          preview = Adoption.preview(request, Inventory.rows(request.model))
          clusters = preview.fetch("collision_clusters").each_with_object({}) do |keys, found|
            keys.each { |key| found[key] = keys.first }
          end
          rows = preview.fetch("sources").map do |source|
            source.merge("cluster" => clusters[source.fetch("key")])
                  .merge(OccurrencePath.bounded_names(source.slice("name")))
          end
          rows.sort_by! { |source| source.fetch("key") }
          page, next_cursor = Pages.bounded(request, SOURCES_LIST, rows, :key => ->(source) { source.fetch("key") })
          preview.slice("required", "suggested_segment").merge("sources" => page, "next_cursor" => next_cursor,
                                                               "total" => rows.length)
        end

        def install_actions(feature)
          feature.action("#{PREFIX}.manage", :description => "Save one complete guarded collection draft atomically.",
                                             :params => describe_params(MANAGE), :result => RESULT,
                                             :refuses => REFUSALS,
                                             :undo_name => "Manage Zone Options", :examples => [manage_example],
                                             :side_effects => "Writes choices and all references atomically.") do |
                                                 request, proposal|
            values = request.params
            Options.manage(
              request, proposal, :collection => values.fetch("collection"),
                                 :options => values.fetch("options"),
                                 :expected_options => values.fetch("expected_options"),
                                 :default_segment_id => values.fetch("default_segment_id"),
                                 :expected_default_segment_id => values.fetch("expected_default_segment_id"),
                                 :replacements => values.fetch("replacements")
            )
          end
          adoption_params = describe_params(Shapes.object({ "mappings" => Shapes.list(MAPPING) }))
          feature.action("#{PREFIX}.adopt", :description => "Explicitly adopt legacy/copied Zone and stamp choices.",
                                            :params => adoption_params,
                                            :result => RESULT, :refuses => REFUSALS, :undo_name => "Adopt Zone Options",
                                            :examples => [{ "mappings" => [] }],
                                            :side_effects => "Converts choices and stamps atomically.") do |
                                                request, proposal|
            Adoption.apply(request, proposal, :mappings => request.params.fetch("mappings"))
          end
        end

        def install_retargeters(feature)
          KINDS.each do |collection, kind|
            feature.reference_retargeter("#{PREFIX}.retarget_#{collection}", :target_kind => kind.id) do |
                 request, proposal, from:, to:|
              Options.rewrite(request, proposal, collection, { from => to })
            end
          end
        end

        PARAM_DESCRIPTIONS = {
          "collection" => "Building Segment or Level collection to read or edit.",
          "options" => "Complete final collection; additions have temporary new: IDs.",
          "expected_options" => "Complete collection last read; a change refuses.",
          "default_segment_id" => "The final default Segment; temporary IDs are resolved in the batch.",
          "expected_default_segment_id" => "The default Segment last read.",
          "replacements" => "Removed option IDs mapped to survivors, or null for explicit Level clearing.",
          "mappings" => "One explicit destination/survivor mapping for every adoption source.",
          "id" => "The stable option ID to read or edit.", "values" => "The option's name and colour.",
          "expected_values" => "The name and colour last read; a change refuses.",
          "user_data" => "JSON-compatible contributor metadata preserved locally.",
          "replacement_id" => "A surviving replacement; null explicitly clears a Level.",
          "target_id" => "The surviving option receiving all source references.",
          "limit" => "Maximum options returned on this page.", "cursor" => "Cursor from the previous page."
        }.freeze

        def describe_params(schema)
          copy = DeepCopy.call(schema)
          copy.fetch("properties").each { |key, field| field["description"] ||= PARAM_DESCRIPTIONS.fetch(key) }
          copy
        end

        def all_result
          usage = Shapes.object({ "live" => Shapes::COUNT, "recoverable" => Shapes::COUNT })
          segments = Shapes.list(Shapes.with(SEGMENTS.descriptor.view_schema, "usage" => usage))
          Shapes.object({ "building_segments" => segments,
                          "levels" => Shapes.list(Shapes.with(LEVELS.descriptor.view_schema, "usage" => usage)),
                          "default_segment_id" => { "type" => %w[string null] }, "adoption" => ADOPTION })
        end

        def manage_example
          { "collection" => "level", "options" => [], "expected_options" => [], "default_segment_id" => nil,
            "expected_default_segment_id" => nil, "replacements" => {} }
        end
      end
    end
  end
end
