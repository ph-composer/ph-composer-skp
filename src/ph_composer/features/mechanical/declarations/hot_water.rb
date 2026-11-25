# frozen_string_literal: true

module PhComposer
  module Mechanical
    # What the hot water catalogs register: the three kinds, and for each a bounded list, the all read with its
    # snapshot section, and create, update, duplicate and delete. Every write goes through the record engine, one
    # native Undo step each. A System's rows add the Zones it serves, its findings and its Heater and Tank counts; its
    # delete moves or clears the Zones naming it, from Serves, moves its Heaters and Tanks to a replacement, and hands
    # every other referrer to the foundation's reference retargeting, which names no feature.
    module HotWaterRegistration
      SYSTEMS = HotWater::Systems::KIND
      HEATERS = HotWater::Heaters::KIND
      TANKS = HotWater::Tanks::KIND
      PREFIXES = { SYSTEMS.id => "#{FEATURE_ID}.hot_water_systems", HEATERS.id => "#{FEATURE_ID}.hot_water_heaters",
                   TANKS.id => "#{FEATURE_ID}.hot_water_tanks" }.freeze
      PAGE = VentilatorRegistration::PAGE
      CREATE = (VentilatorRegistration::CREATE + %w[reference.invalid]).sort.freeze
      EDIT = VentilatorRegistration::EDIT
      DUPLICATE = VentilatorRegistration::DUPLICATE
      # A delete scans every record for references to it, so an unreadable record anywhere refuses it. A System's
      # reads the Zones naming it, and the dispatcher adds the refusals of Zones' participant, which stages the moves.
      MEMBER_DELETE = %w[copy.rule_missing record.unreadable reference.in_use reference.invalid target.ambiguous
                         target.changed target.not_found validation.failed].freeze
      SYSTEM_DELETE = VentilatorRegistration::DELETE
      SYSTEM_REFERENCE = "The Hot Water System it belongs to, which must exist."
      FINDINGS = ServesRegistration::FINDINGS
      COUNT = { "type" => "integer", "minimum" => 0 }.freeze
      ROWS = {
        SYSTEMS.id => Shapes.with(Shapes.row(SYSTEMS), ServesRegistration::SERVED.merge(
          "heater_count" => Shapes.described(COUNT, "How many readable Heaters name it."),
          "tank_count" => Shapes.described(COUNT, "How many readable Tanks name it.")
        )),
        HEATERS.id => Shapes.row(HEATERS),
        TANKS.id => Shapes.with(Shapes.row(TANKS), {
          "slot" => Shapes.described({ "type" => %w[string null],
                                       "enum" => HotWater::Slotting::SLOTS + [nil] },
                                     "The System's tank slot it fills at export; null when " \
                                     "its role has none free."),
          "findings" => FINDINGS
        })
      }.freeze
      DESCRIPTIONS = {
        SYSTEMS.id => "Unless values give them, its tap points and piping calculation method are absent.",
        HEATERS.id => "Unless values give them, it is an electric heater covering all the System's hot water, in " \
                      "conditioned space. A monthly heat pump takes honeybee-ph's COP 2.5 at -8.333 C and at " \
                      "8.333 C; an annual or inside heat pump needs its value.",
        TANKS.id => "Unless values give them, it is one 300 L storage tank for hot water only in conditioned space, " \
                    "with honeybee-ph's default losses (standby 4.0 W/K, fraction 0.3) at 20 C room and 60 C water."
      }.freeze
      SYSTEM_EXAMPLE = "hws_Ab12Cd34Ef56"
      CREATE_EXAMPLES = {
        SYSTEMS.id => { "values" => { "name" => "HWS-1", "number_tap_points" => 8 } },
        HEATERS.id => { "values" => { "name" => "H-HP", "hot_water_system_id" => SYSTEM_EXAMPLE,
                                      "variant" => "heat_pump_annual", "percent_coverage" => 0.7,
                                      "total_system_perf_ratio" => 2.5 } },
        TANKS.id => { "values" => { "name" => "T1", "hot_water_system_id" => SYSTEM_EXAMPLE, "role" => "storage",
                                    "storage_capacity_l" => 300 } }
      }.freeze
      UPDATE_EXAMPLES = {
        SYSTEMS.id => { "values" => { "number_tap_points" => 10 }, "expected_values" => { "number_tap_points" => 8 } },
        HEATERS.id => { "values" => { "variant" => "electric", "total_system_perf_ratio" => nil },
                        "expected_values" => { "variant" => "heat_pump_annual" } },
        TANKS.id => { "values" => { "role" => "buffer" }, "expected_values" => { "role" => "storage" } }
      }.freeze
      LIST_EXAMPLES = [{}, { "limit" => 20 }, { "fields" => %w[values export_ready] }].freeze

      module_function

      def install(feature)
        [SYSTEMS, HEATERS, TANKS].each do |kind|
          feature.record_kind(kind)
          install_reads(feature, kind)
          install_create_and_update(feature, kind)
          install_duplicate(feature, kind)
        end
        install_system_delete(feature)
        [HEATERS, TANKS].each { |kind| install_member_delete(feature, kind) }
      end

      def install_reads(feature, kind)
        prefix = PREFIXES.fetch(kind.id)
        row = ROWS.fetch(kind.id)
        list = HotWater::Reads::LISTS.fetch(kind.id)
        refuses = kind == SYSTEMS ? Serves::State::REFUSES : []
        params = DefinitionLists.params(row).tap do |schema|
          schema["properties"]["ids"]["items"] = Shapes.id(kind.id_prefix, "A #{kind.label} id.")
        end
        feature.query(list, :description => "One bounded page of #{kind.label}s in id order#{read_detail(kind)}.",
                            :refuses => PAGE + refuses, :params => params,
                            :result => DefinitionLists.result(row, :paged => true),
                            :examples => LIST_EXAMPLES) do |request|
          HotWater::Reads.list(request, kind.id, :extra => extra(request, kind))
        end
        feature.query("#{prefix}.all", :description => "Every #{kind.label}#{read_detail(kind)}, for the panel " \
                                                       "snapshot.",
                                       :response => { "bounded" => false, "prefer" => list },
                                       :refuses => refuses, :params => Shapes::NONE,
                                       :result => DefinitionLists.result(row, :paged => false),
                                       :examples => [{}]) do |request|
          HotWater::Reads.all(request, kind.id, :extra => extra(request, kind))
        end
        feature.snapshot_section(prefix, :query => "#{prefix}.all")
      end

      def read_detail(kind)
        case kind
        when SYSTEMS then ", with export readiness, the Zones each serves, its Heater and Tank counts and findings, " \
                          "among them the Building Segment pooling note and a piping calculation method the export " \
                          "leaves out"
        when TANKS then ", with export readiness and the System tank slot each fills"
        else ", with export readiness"
        end
      end

      # What a row adds beside the record: a System's Zones, findings and counts, from one Zones read;
      # a Tank's slot. A Heater adds nothing.
      def extra(request, kind)
        case kind
        when SYSTEMS then system_extra(request)
        when TANKS then HotWater::Reads.tank_extra(request)
        end
      end

      def system_extra(request)
        zones = Serves::State.zones(request)
        usage = Serves::Reads.usage(request, SYSTEMS.id, :zones => zones)
        members = HotWater::Reads.system_extra(request)
        systems = HotWater::Reads.members(request.engine, SYSTEMS.id).to_h { |record| [record.fetch("id"), record] }
        pooled = HotWaterPlan.pooled(ExportZones.live(zones).select(&:exported), systems).group_by(&:record_id)
        lambda do |record|
          notes = pooled.fetch(record.fetch("id"), []).map { |found| Codes.finding(found.code, "info", found.message) }
          method = HotWater::Systems.method_not_exported(record)
          notes << Codes.finding(Codes::METHOD_NOT_EXPORTED, "info", method) if method
          served = usage.call(record)
          served.merge(members.call(record)).merge("findings" => served.fetch("findings") + notes)
        end
      end

      def install_create_and_update(feature, kind)
        prefix = PREFIXES.fetch(kind.id)
        preconditions = ["Its name, trimmed and in any case, is not another #{kind.label}'s."]
        preconditions << SYSTEM_REFERENCE unless kind == SYSTEMS
        feature.action("#{prefix}.create",
                       :description => "Create one #{kind.label}. #{DESCRIPTIONS.fetch(kind.id)}",
                       :refuses => CREATE, :params => create_params(kind), :result => Shapes::RESULT,
                       :undo_name => "Create #{kind.label}", :preconditions => preconditions,
                       :side_effects => "Creates one Model-owned definition.",
                       :examples => [CREATE_EXAMPLES.fetch(kind.id)]) do |request, proposal|
          HotWater::Operations.create(request, proposal, kind.id, :values => request.params.fetch("values"),
                                                                  :user_data => request.params["user_data"])
        end
        feature.action("#{prefix}.update",
                       :description => "Edit guarded values of one #{kind.label}; a changed expected value refuses " \
                                       "and writes nothing.#{update_detail(kind)}",
                       :refuses => EDIT, :params => Shapes.update(kind), :result => Shapes::RESULT,
                       :undo_name => "Edit #{kind.label}",
                       :preconditions => ["The #{kind.label} exists and is readable.",
                                          "A new name is not another #{kind.label}'s."],
                       :side_effects => "Updates one definition and preserves its metadata.",
                       :examples => [{ "id" => Shapes.example_id(kind) }
                                       .merge(UPDATE_EXAMPLES.fetch(kind.id))]) do |request, proposal|
          params = request.params
          HotWater::Operations.update(request, proposal, kind.id, :id => params.fetch("id"),
                                                                  :values => params.fetch("values"),
                                                                  :expected_values => params.fetch("expected_values"))
        end
      end

      # A Heater or Tank names its System when it is created.
      def create_params(kind)
        params = Shapes.create(kind)
        return params if kind == SYSTEMS

        values = params.fetch("properties").fetch("values")
        params.merge("properties" => params.fetch("properties").merge(
          "values" => values.merge("required" => values.fetch("required") + ["hot_water_system_id"])
        ))
      end

      def update_detail(kind)
        return "" unless kind == HEATERS

        " A new variant takes its own efficiency values and nulls the old variant's in the same edit."
      end

      def install_duplicate(feature, kind)
        feature.action("#{PREFIXES.fetch(kind.id)}.duplicate",
                       :description => "Duplicate one #{kind.label} with a new id and source derived.",
                       :refuses => DUPLICATE, :params => Shapes.duplicate(kind), :result => Shapes::RESULT,
                       :undo_name => "Duplicate #{kind.label}", :preconditions => ["The #{kind.label} exists and is " \
                                                                                   "readable."],
                       :side_effects => "Creates one definition; user_data is copied.",
                       :examples => [{ "id" => Shapes.example_id(kind) }]) do |request, proposal|
          HotWater::Operations.duplicate(request, proposal, kind.id, :id => request.params.fetch("id"),
                                                                     :name => request.params["name"])
        end
      end

      # A Heater or Tank: nothing names it, so the engine's guarded delete.
      def install_member_delete(feature, kind)
        feature.action("#{PREFIXES.fetch(kind.id)}.delete",
                       :description => "Delete one #{kind.label}.",
                       :refuses => MEMBER_DELETE, :params => Shapes.delete(kind),
                       :result => Shapes.with_removed_user_data(Shapes::RESULT),
                       :undo_name => "Delete #{kind.label}", :preconditions => ["The #{kind.label} exists and is " \
                                                                                "readable."],
                       :side_effects => "Deletes one definition and its metadata; Undo restores it.",
                       :examples => [{ "id" => Shapes.example_id(kind) }]) do |request, proposal|
          HotWater::Operations.delete(request, proposal, kind.id, :id => request.params.fetch("id"),
                                                                  :expected_values => request.params.fetch(
                                                                    "expected_values", {}
                                                                  ))
        end
      end

      # A System: the Zones naming it move or empty, from Serves; its Heaters and Tanks move to a replacement, and
      # with none they keep it in use.
      def install_system_delete(feature)
        params = Shapes.delete(SYSTEMS).then do |schema|
          schema["properties"]["replacement_id"] =
            Shapes.id(SYSTEMS.id_prefix, "The Hot Water System that takes this one's place on every Zone, Heater, " \
                                         "Tank and other record naming it, or null to empty the Zones' slots and " \
                                         "clear other features' records. Needed while anything names it; null " \
                                         "leaves Heaters and Tanks in use.", :nullable => true)
          schema
        end
        feature.action("#{PREFIXES.fetch(SYSTEMS.id)}.delete",
                       :description => "Delete one Hot Water System. While a Zone, Heater or Tank names it, name a " \
                                       "replacement_id, which takes its place on each of them; null empties the " \
                                       "Zones' slots, and a Heater or Tank still naming it refuses. Without one it " \
                                       "refuses as reference.in_use.",
                       :refuses => SYSTEM_DELETE, :params => params,
                       :result => Shapes.with_removed_user_data(Shapes::RESULT),
                       :participants => [Serves::State::STAGE], :undo_name => "Delete Hot Water System",
                       :preconditions => ["The Hot Water System exists and is readable."],
                       :side_effects => "Deletes one definition and its metadata, and rewrites the Zones, Heaters " \
                                        "and Tanks that name it and, with replacement_id or null, any other " \
                                        "feature's records that name it; Undo restores all of them.",
                       :examples => [{ "id" => Shapes.example_id(SYSTEMS) },
                                     { "id" => Shapes.example_id(SYSTEMS),
                                       "replacement_id" => "hws_Zy98Xw76Vu54" }]) do |request, proposal|
          params = request.params
          id = params.fetch("id")
          expected = params.fetch("expected_values", {})
          replacement = params.fetch("replacement_id", Serves::Operations::KEEP)
          Serves::Operations.delete(request, proposal, SYSTEMS.id, :id => id, :expected_values => expected,
                                                                   :replacement => replacement) do |plan|
            if replacement.is_a?(String)
              HotWater::Operations.move_members(request, proposal, :from => id, :to => replacement)
            end
            unless replacement.equal?(Serves::Operations::KEEP)
              plan = CatalogOperations.with_retargeted(request, plan, SYSTEMS.id, :from => id, :to => replacement)
            end
            HotWater::Operations.delete(request, proposal, SYSTEMS.id, :id => id, :expected_values => expected,
                                                                       :reference_plan => plan)
          end
        end
      end
    end
  end
end
