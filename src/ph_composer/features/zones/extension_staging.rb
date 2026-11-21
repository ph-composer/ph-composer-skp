# frozen_string_literal: true

module PhComposer
  module Zones
    # The one route by which a feature that requires Zones writes its own structured extension on Zone and Building
    # Segment records inside its own action (context/EXTENSIBILITY.md, "Building Segment settings"): the
    # proposal participant `ph_composer.zones.stage_extension`. Zones checks each payload with the namespace's
    # installed validator and stages it in the caller's proposal, so the caller's write and Zones' land in one Undo
    # step and no other feature writes a Zone or Segment record. Zones never reads the payload.
    #
    # A Zone is an entity record, so its payload is one Zone update step on the occurrence the reference names,
    # refused as any Zone write is (a locked or shared Zone). A Zone an earlier step of the same proposal writes (a
    # Segment rename rewriting its evidence) is staged from that step's result, so the two apply in turn. A Segment
    # is a catalog record, staged as Save stages it. A payload equal to what is stored stages nothing. The result
    # names what changed, and gives each changed Zone as a reference entry, so a caller that deletes a record its
    # Zones stop naming can plan the delete.
    module ExtensionStaging
      NAME = "#{FEATURE_ID}.stage_extension"
      ZONE_TARGET = Shapes.object({ "reference" => ZONE_REFERENCE, "payload" => { "type" => "object" } })
      SEGMENT_TARGET = Shapes.object({ "id" => SchemaShapes.id("bsg", "The Building Segment."),
                                       "payload" => { "type" => "object" } })
      PARAMS = Shapes.object({
        "namespace" => { "type" => "string", "minLength" => 1,
                         "description" => "The calling feature's own extension namespace." },
        "zones" => Shapes.list(ZONE_TARGET, :description => "Each Zone occurrence and its whole new payload."),
        "segments" => Shapes.list(SEGMENT_TARGET, :description => "Each Building Segment and its whole new payload.")
      }, :optional => %w[zones segments]).freeze
      ENTRY = Shapes.object({ "kind" => { "type" => "string" }, "key" => { "type" => "array" },
                              "record" => { "type" => "object" } }).freeze
      RESULT = Shapes.object({
        "zone_ids" => Shapes.list(Shapes::ID, :description => "The Zones whose payload changed."),
        "segment_ids" => Shapes.list(Shapes::ID, :description => "The Segments whose payload changed."),
        "zone_entries" => Shapes.list(ENTRY, :description => "Each changed Zone as the proposal leaves it, as a " \
                                                             "reference entry: what a caller's reference plan " \
                                                             "projects when it deletes a record the Zones no " \
                                                             "longer name.")
      }).freeze
      REFUSES = %w[extension.invalid extension.migration_required extension.schema_unsupported extension.unavailable
                   reference.invalid record.unreadable target.ambiguous target.changed target.locked
                   target.not_found target.shared_definition target.wrong_hierarchy target.wrong_kind
                   validation.failed].freeze
      EXAMPLE = { "namespace" => "example.segment.note",
                  "segments" => [{ "id" => "bsg_Ab12Cd34Ef56", "payload" => { "text" => "Note" } }] }.freeze

      module_function

      def install(feature)
        feature.proposal_participant(NAME,
                                     :description => "Stage the calling feature's extension payload on named Zone " \
                                                     "and Building Segment records in its own proposal, checked by " \
                                                     "the namespace's installed validator.",
                                     :params => PARAMS, :result => RESULT, :refuses => REFUSES,
                                     :examples => [EXAMPLE]) do |request, proposal|
          params = request.params
          stage(request, proposal, params.fetch("namespace"), :zones => params.fetch("zones", []),
                                                              :segments => params.fetch("segments", []))
        end
      end

      def stage(request, proposal, namespace, zones:, segments:)
        ids = zones.map { |target| target.dig("reference", "zone_id") }
        raise CodedError.new("params.invalid", "A Zone may appear only once.") if ids.uniq.length != ids.length

        staged = zones.filter_map { |target| stage_zone(request, proposal, namespace, target) }
        segment_ids = segments.filter_map do |target|
          id = target.fetch("id")
          before = request.engine.find(Options::SEGMENT_KIND, id, :change_set => proposal)
          changed = Options::SegmentSettings.stage_extensions(request, proposal, Options::SEGMENT_KIND, id,
                                                              { namespace => target.fetch("payload") },
                                                              before.fetch("extension_data", {}))
          id unless changed.empty?
        end
        entries = staged.map { |path, record| { "kind" => REFERENCE_KIND, "key" => path, "record" => record } }
        { "zone_ids" => staged.map { |_path, record| record.fetch("id") }, "segment_ids" => segment_ids,
          "zone_entries" => entries }
      end

      def stage_zone(request, proposal, namespace, target)
        reference = target.fetch("reference")
        zone = Occurrences.resolve_editable_zone(request.model, reference)
        before = staged_record(proposal, zone.record)
        update = { "expected_metadata" => { "user_data" => before.fetch("user_data", {}),
                                            "extension_data" => before.fetch("extension_data", {}) },
                   "extension_payloads" => { namespace => target.fetch("payload") } }
        after = Records::Metadata.planned(request.engine, request.registry.catalog, before, update, "Zone")
        Schema.validate!(after)
        return nil if after == before

        proposal.add_step(UpdateZoneStep.new(:reference => zone.reference, :before => before, :after => after),
                          :scopes => [Operations::EntityScope.new(zone.reference.fetch("zone_path")[0...-1])])
        [zone.path, after]
      end

      # The Zone record as the proposal leaves it: the result of the last step it holds that writes that Zone's
      # record (a Zone update, or the evidence a Segment rename rewrites), else the record as stored.
      def staged_record(proposal, record)
        id = record.fetch("id")
        proposal.steps.reverse_each do |step|
          staged = written(step.descriptor, id)
          return DeepCopy.call(staged) if staged
        end
        record
      end

      def written(descriptor, id)
        case descriptor["name"]
        when "update_zone" then descriptor.fetch("after") if descriptor.dig("after", "id") == id
        when "rewrite_zone_options"
          descriptor.fetch("writes").reverse.find do |write|
            write.fetch("dictionary") == ZONE_STORE.dictionary && write.dig("after", "id") == id
          end&.fetch("after")
        end
      end
    end
  end
end
