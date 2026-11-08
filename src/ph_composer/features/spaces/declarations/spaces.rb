# frozen_string_literal: true

module PhComposer
  module Spaces
    # The reads' public contract: the three reference targets, `list`, `all` and the panel's section.
    module Registration
      AREA = Shapes.quantity("m2", "Plan area, projected onto the horizontal plane.")
      FINDING = Shapes.object({ "code" => Shapes::TEXT, "message" => Shapes::TEXT,
                                "blocks_export" => { "type" => "boolean" },
                                "repair" => { "type" => "string", "enum" => %w[make_independent restore_position],
                                              "description" => "The operation that repairs it, when one does." } },
                              :optional => %w[repair])
      FINDINGS = Shapes.list(FINDING)
      EXTENSION_STATUS = { "type" => "object",
                           "description" => "Each extension envelope's status against what is installed." }.freeze
      AIRFLOWS = Shapes.object(AIRFLOWS.to_h do |key|
        [key, Shapes.quantity("m3/h", "The rate the Space contributes: a set value, 0 when unset in a " \
                                      "user-specified Space, null in an inheriting one.", :nullable => true)]
      end)
      SEGMENT_METRICS = Shapes.object({
        "floor_area_m2" => AREA,
        "weighted_area_m2" => Shapes.quantity("m2", "Area times weighting factor."),
        "net_area_m2" => Shapes.quantity("m2", "Area times net area factor."),
        "horizontal" => { "type" => "boolean" }
      })
      VOLUME_METRICS = Shapes.object({
        "floor_area_m2" => AREA,
        "weighted_area_m2" => Shapes.quantity("m2", "Summed weighted area."),
        "net_area_m2" => Shapes.quantity("m2", "Summed net area."),
        "net_volume_m3" => Shapes.quantity("m3", "Net area times height; null " \
                                                 "until a height is entered.",
                                           :nullable => true)
      })
      SPACE_METRICS = Shapes.object({
        "floor_area_m2" => AREA,
        "weighted_area_m2" => Shapes.quantity("m2", "Summed weighted area."),
        "net_area_m2" => Shapes.quantity("m2", "Summed net area."),
        "net_volume_m3" => Shapes.quantity("m3", "Summed over Volumes with a height."),
        "average_height_m" => Shapes.quantity("m", "Floor-area-weighted, read only.",
                                              :nullable => true)
      })
      ZONE_REFERENCE = Shapes.object({ "zone_id" => Shapes::TEXT, "zone_path" => Shapes::ZONE_PATH })

      def self.row(kind, extra)
        Shapes.with(kind.descriptor.view_schema, { "extension_status" => EXTENSION_STATUS }.merge(extra))
      end

      SEGMENT_ROW = row(FLOOR_SEGMENT, "reference" => FLOOR_SEGMENT_REFERENCE, "metrics" => SEGMENT_METRICS,
                                       "findings" => FINDINGS,
                                       "weighting_band" => { "type" => "string",
                                                             "description" => "The weighting factor as By weighting " \
                                                                              "factor's legend and a filter key it." })
      VOLUME_ROW = row(VOLUME, "reference" => VOLUME_REFERENCE, "nested" => { "type" => "boolean" },
                               "open" => { "type" => "boolean", "description" => "Open for editing on the path." },
                               "protected" => { "type" => "boolean", "description" => "Locked, so the Space " \
                                                                                      "selects it whole." },
                               "moved" => { "type" => "boolean", "description" => "Away from where it was " \
                                                                                  "last left." },
                               "metrics" => VOLUME_METRICS, "findings" => FINDINGS,
                               "floor_segments" => Shapes.list(SEGMENT_ROW))
      SPACE_ROW = row(SPACE, "reference" => SPACE_REFERENCE,
                             "zone" => ZONE_REFERENCE.merge("type" => %w[object null],
                                                            "description" => "The Zone whose Group holds the " \
                                                                             "Space, or null outside every Zone."),
                             "state" => { "type" => "string", "enum" => %w[found ambiguous shared_definition] },
                             "nested" => { "type" => "boolean" }, "metrics" => SPACE_METRICS,
                             "airflow_mode" => { "type" => "string", "enum" => %w[inheriting user_specified] },
                             "airflows" => AIRFLOWS, "findings" => FINDINGS, "volumes" => Shapes.list(VOLUME_ROW))
      ZONE_ROW = Shapes.object({
        "zone_id" => Shapes::TEXT, "zone_path" => Shapes::ZONE_PATH,
        "name" => { "type" => %w[string null] }, "space_count" => Shapes::COUNT,
        "floor_area_m2" => AREA,
        "weighted_area_m2" => Shapes.quantity("m2", "Summed weighted area (iCFA)."),
        "net_volume_m3" => Shapes.quantity("m3", "Summed net volume."),
        "airflows" => Shapes.object(AIRFLOWS.fetch("properties").transform_values do |field|
          field.merge("description" => "Summed over user-specified Spaces; null while " \
                                       "any Space inherits.")
        end),
        "inheriting_count" => Shapes::COUNT
      })
      TOTAL_PROPERTIES = {
        "floor_area_m2" => AREA, "weighted_area_m2" => Shapes.quantity("m2", "Summed weighted area (iCFA)."),
        "net_volume_m3" => Shapes.quantity("m3", "Summed net volume.")
      }.freeze
      BUILDING_SEGMENT_ROW = Shapes.object({ "key" => Shapes::TEXT, "name" => { "type" => %w[string null] },
                                             "zone_count" => Shapes::COUNT }.merge(TOTAL_PROPERTIES))
      STRAY = Shapes.with(FINDING, "reference" => { "type" => "object",
                                                    "description" => "The misplaced record's reference." })
      ALL_RESULT = Shapes.object({
        "spaces" => Shapes.list(SPACE_ROW, :description => "Every Space occurrence."),
        "zones" => Shapes.list(ZONE_ROW, :description => "Each Zone's sums."),
        "building_segments" => Shapes.list(BUILDING_SEGMENT_ROW,
                                           :description => "Each Building-Segment's sums " \
                                                           "over its Zones."),
        "model" => Shapes.object(TOTAL_PROPERTIES,
                                 :description => "Sums over every Space in the Model."),
        "findings" => Shapes.list(STRAY, :description => "Records outside the " \
                                                         "hierarchy that holds them."),
        "units" => Shapes.object(Reads::UNITS.to_h { |key, unit|
          [key, { "type" => "string", "enum" => [unit] }]
        })
      })
      def self.fields(allowed)
        { "type" => "array", "items" => { "type" => "string", "enum" => allowed },
          "description" => "What each row carries beside its id and reference. Absent, every field but the " \
                           "metadata (user_data, extension_data, extension_status) and loops_m." }
      end

      def self.paged(key, row, description)
        Shapes.object({ key => Shapes.list(row, :description => description), "next_cursor" => Pages::NEXT_CURSOR,
                        "total" => Pages::TOTAL, "units" => ALL_RESULT.dig("properties", "units") })
      end

      PAGE = { "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR }.freeze
      LIST_PARAMS = Shapes.object({
        "ids" => { "type" => "array", "items" => Shapes::TEXT,
                   "maxItems" => Pages::MAXIMUM_LIMIT,
                   "description" => "Only occurrences of these Space ids." },
        "fields" => fields(Summaries::SPACE_FIELDS)
      }.merge(PAGE), :optional => %w[ids fields limit cursor])
      # A summary row: identity always, the rest as `fields` asks. Children and findings are counted here
      # and read through the scoped reads.
      def self.summary(row, drop, extra)
        { "type" => "object", "required" => %w[id schema_version reference],
          "properties" => row.fetch("properties").reject { |key, _value| drop.include?(key) }.merge(extra) }.freeze
      end

      FINDING_COUNTS = { "type" => "object", "description" => "Findings by code, its children's too." }.freeze
      SUMMARY_ROW = summary(SPACE_ROW, %w[volumes findings],
                            "building_segment" => { "type" => %w[string null] }, "volume_count" => Shapes::COUNT,
                            "floor_segment_count" => Shapes::COUNT, "finding_counts" => FINDING_COUNTS)
      LIST_EXAMPLES = [{}, { "limit" => 20, "fields" => %w[values metrics] }].freeze
      ZONE_SUMS = Shapes.object(ZONE_ROW.fetch("properties").slice("zone_id", "zone_path", "name", "space_count")
                                        .merge(TOTAL_PROPERTIES))
      LIST_RESULT = Shapes.object({
        "spaces" => Shapes.list(SUMMARY_ROW, :description => "One page in path order, within the reply budget."),
        "model" => ALL_RESULT.dig("properties", "model"),
        "zones" => Shapes.list(ZONE_SUMS, :description => "The sums of the Zones this page's Spaces are in."),
        "building_segments" => Shapes.list(BUILDING_SEGMENT_ROW,
                                           :description => "The sums of this page's Building-Segments."),
        "stray_finding_count" => Shapes::COUNT, "units" => ALL_RESULT.dig("properties", "units"),
        "next_cursor" => Pages::NEXT_CURSOR, "total" => Pages::TOTAL
      })
      VOLUME_SUMMARY = summary(VOLUME_ROW, %w[floor_segments], "floor_segment_count" => Shapes::COUNT)
      LOOPS = { "type" => "array", "x-unit" => "m",
                "items" => { "type" => "array", "items" => { "type" => "array", "items" => { "type" => "number" } } },
                "description" => "The Face's outer loop then its holes, each a list of [x, y, z] points in model " \
                                 "space. Only when `fields` asks for it." }.freeze
      SEGMENT_SUMMARY = summary(SEGMENT_ROW, [], "loops_m" => LOOPS)
      REFUSAL = { "type" => %w[object null], "required" => %w[code message],
                  "properties" => { "code" => Shapes::TEXT, "message" => Shapes::TEXT },
                  "description" => "What `operation` would refuse with now, or null when it would accept." }.freeze
      CANDIDATE_ROW = { "type" => "object",
                        "required" => %w[entity_path candidate space volume operation refusal requires],
                        "properties" => {
                          "entity_path" => Shapes::ZONE_PATH.merge("description" => "The Face's path from the root."),
                          "candidate" => { "type" => "string", "enum" => %w[floor volume],
                                           "description" => "floor: in a Volume, to mark; volume: loose at a " \
                                                            "Space's root, to group into a new Volume." },
                          "space" => SPACE_REFERENCE.merge("type" => %w[object null]),
                          "volume" => VOLUME_REFERENCE.merge("type" => %w[object null]),
                          "operation" => Shapes::TEXT, "refusal" => REFUSAL,
                          "requires" => { "type" => %w[string null],
                                          "description" => "What the operation needs first." },
                          "plan_area_m2" => AREA,
                          "normal" => { "type" => "array", "items" => { "type" => "number" } },
                          "horizontal" => { "type" => "boolean" },
                          "loops_m" => LOOPS
                        } }.freeze
      SCOPED_FINDING = Shapes.with(FINDING, "reference" => { "type" => "object",
                                                             "description" => "What the finding is about." })
      # What the Spaces walk refuses, and what the Zones read it depends on can.
      READ = %w[geometry.invalid record.unreadable target.wrong_kind validation.failed].freeze

      module_function

      def targets
        [[SPACE, SPACE_REFERENCE, ->(scan) { scan.spaces }],
         [VOLUME, VOLUME_REFERENCE, ->(scan) { scan.volumes + scan.orphan_volumes }],
         [FLOOR_SEGMENT, FLOOR_SEGMENT_REFERENCE, ->(scan) { scan.segments + scan.misplaced_segments }]]
          .map do |kind, reference, occurrences|
          Records::ReferenceTarget.new(
            :id => kind.id, :label => kind.label, :schema_version => kind.schema_version,
            :values => kind.values_schema, :occurrence => reference, :references => kind.references,
            :validate => ->(record) { kind.problems(record) },
            # The inventory answers which ids exist. A record that does not read cannot be a reference's
            # target or a holder of one, so it is left out rather than refusing every resolution in the
            # Model; a reference to it still refuses as naming nothing.
            :records => lambda { |model|
              occurrences.call(Occurrences.scan(model, :strict => false)).map do |occurrence|
                Records::ReferenceEntry.new(:kind => kind.id, :key => occurrence.path, :record => occurrence.record)
              end
            }
          )
        end
      end

      def self.scope(reference, what)
        Shapes.described(reference, "The #{what} whose children to read, by the reference a read returned.")
      end

      def install_candidates(feature, refuses, example)
        feature.query(ScopedReads::CANDIDATE_FACES,
                      :description => "One page of the Faces of one Space or one Volume that carry no record yet: " \
                                      "Floor candidates inside a Volume (for floors.mark) and loose Faces at the " \
                                      "Space's root (for volumes.create), each with the refusal its operation would " \
                                      "give now. Name exactly one.",
                      :refuses => refuses, :examples => [{ "space" => example }],
                      :params => Shapes.object({ "space" => scope(SPACE_REFERENCE, "Space"),
                                                 "volume" => scope(VOLUME_REFERENCE, "Volume"),
                                                 "fields" => fields(ScopedReads::CANDIDATE_FIELDS) }.merge(PAGE),
                                               :optional => %w[space volume fields limit cursor]),
                      :result => Shapes.object({ "candidate_faces" => Shapes.list(CANDIDATE_ROW),
                                                 "next_cursor" => Pages::NEXT_CURSOR,
                                                 "total" => Pages::TOTAL })) do |request|
          ScopedReads.candidate_faces(request)
        end
      end

      def install_scoped(feature)
        refuses = READ + %w[query.cursor_expired query.limit_invalid target.not_found target.changed]
        example = { "space_id" => "spc_Ab12Cd34Ef56", "entity_path" => [1201, 1202] }
        feature.query(ScopedReads::VOLUMES,
                      :description => "One page of one Space's Volumes, each with its Floor Segment count.",
                      :refuses => refuses, :examples => [{ "space" => example }],
                      :params => Shapes.object({ "space" => scope(SPACE_REFERENCE, "Space"),
                                                 "fields" => fields(Summaries::VOLUME_FIELDS) }.merge(PAGE),
                                               :optional => %w[fields limit cursor]),
                      :result => paged("volumes", VOLUME_SUMMARY, "One page in path order.")) do |request|
          ScopedReads.volumes(request)
        end
        feature.query(ScopedReads::FLOOR_SEGMENTS,
                      :description => "One page of the Floor Segments of one Space or one Volume: name exactly one.",
                      :refuses => refuses, :examples => [{ "space" => example }],
                      :params => Shapes.object({ "space" => scope(SPACE_REFERENCE, "Space"),
                                                 "volume" => scope(VOLUME_REFERENCE, "Volume"),
                                                 "fields" => fields(Summaries::SEGMENT_FIELDS) }.merge(PAGE),
                                               :optional => %w[space volume fields limit cursor]),
                      :result => paged("floor_segments", SEGMENT_SUMMARY, "One page in path order.")) do |request|
          ScopedReads.floor_segments(request)
        end
        install_candidates(feature, refuses, example)
        feature.query(ScopedReads::FINDINGS,
                      :description => "One page of the findings of the Model, or of one Space and its children, " \
                                      "each with the reference of what it is about; optionally only some codes. " \
                                      "The Model's include those of Volumes outside every Space and their Floor " \
                                      "Segments.",
                      :refuses => refuses, :examples => [{}, { "codes" => ["space.empty"] }],
                      :params => Shapes.object({ "space" => scope(SPACE_REFERENCE, "Space"),
                                                 "codes" => { "type" => "array", "items" => Shapes::TEXT,
                                                              "description" => "Only findings with these codes." } }
                                                 .merge(PAGE), :optional => %w[space codes limit cursor]),
                      :result => Shapes.object({ "findings" => Shapes.list(SCOPED_FINDING),
                                                 "next_cursor" => Pages::NEXT_CURSOR,
                                                 "total" => Pages::TOTAL })) do |request|
          ScopedReads.findings(request)
        end
      end

      def install(feature)
        targets.each { |target| feature.reference_target(target) }
        feature.query("#{FEATURE_ID}.list",
                      :description => "One page of Space summaries in path order: values, SI metrics, Zone and " \
                                      "Building-Segment, and counts of Volumes, Floor Segments and findings. The " \
                                      "Model's sums cover every Space whatever the filter; the Zone and " \
                                      "Building-Segment sums are those of this page's Spaces.",
                      :refuses => READ + %w[query.cursor_expired query.limit_invalid], :params => LIST_PARAMS,
                      :result => LIST_RESULT, :examples => LIST_EXAMPLES) { |request| Reads.list(request) }
        install_scoped(feature)
        feature.query("#{FEATURE_ID}.all",
                      :response => { "bounded" => false, "prefer" => "#{FEATURE_ID}.list" },
                      :description => "Every Space occurrence in one complete projection, for the panel. Scripts " \
                                      "page #{FEATURE_ID}.list instead.",
                      :refuses => READ, :params => Shapes::NONE, :result => ALL_RESULT,
                      :examples => [{}]) { |request| Reads.all(request) }
        feature.snapshot_section("#{FEATURE_ID}.spaces", :query => "#{FEATURE_ID}.all")
      end
    end
  end
end
