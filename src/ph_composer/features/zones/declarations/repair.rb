# frozen_string_literal: true

module PhComposer
  module Zones
    # Identity and membership repairs: a copied Zone, a natively split Face, an exploded Zone. The
    # handlers are Zones module functions (zone/operations.rb).
    module RepairRegistration
      # The copy is named by path, not by id: its id is the ambiguous thing being repaired.
      REPAIR_PARAMS = Shapes.object({
        "zone_path" => PATH.merge("description" => "The root-to-Zone path of the copy to reidentify, as list " \
                                                   "returns it.")
      }).freeze
      INDEPENDENT_PARAMS = Shapes.object({
        "zone_path" => REPAIR_PARAMS.dig("properties", "zone_path"),
        "copy_added" => { "type" => "array", "items" => { "type" => "integer" },
                          "description" => "The containers one native copy added, by persistent id, so records " \
                                           "outside the Zone that came in the same copy can follow it." }
      }, :optional => ["copy_added"]).freeze
      ISOLATE_PARAMS = Shapes.object({
        "group_path" => PATH.merge("description" => "The root-to-Group path of the copied plain Group.")
      }).freeze
      ISOLATE_RESULT = Shapes.object({
        "isolated" => { "type" => "boolean", "description" => "Whether the Group still shared its contents." }
      }).freeze
      REPAIR_RESULT = Shapes.object({
        "zone_id" => Shapes::ID.merge("description" => "The copy's new Zone id."),
        "retired_pairs" => Shapes::COUNT.merge("description" => "Surface pairs the copy's Faces left behind.")
      }).freeze
      INDEPENDENT_RESULT = Shapes.object({
        "zone_id" => Shapes::ID.merge("description" => "The occurrence's new Zone id."),
        "retired_pairs" => Shapes::COUNT.merge("description" => "Surface pairs the occurrence's Faces left behind."),
        "storage_isolated" => { "type" => "boolean",
                                "description" => "Whether the occurrence's Group, or a Group inside it, " \
                                                 "still shared its contents." }
      }).freeze
      SPLIT_REPAIR_PARAMS = Shapes.object({
        "zone" => ZONE_REFERENCE.merge("description" => "The Zone occurrence holding the split pieces."),
        "face_id" => Shapes::ID.merge("description" => "The Face id the split pieces share."),
        "zones" => { "type" => "array", "items" => ZONE_REFERENCE, "minItems" => 1,
                     "description" => "Every Zone the repair may write, the counterpart's included." },
        "retaining_entity_path" => PATH.merge("description" => "The piece that keeps face_id, when no stored " \
                                                               "endpoint proves it.")
      }, :optional => ["retaining_entity_path"]).freeze
      SPLIT_REPAIR_RESULT = Shapes.object({
        "face_id" => Shapes::ID, "retaining_entity_path" => PATH,
        "retention_basis" => { "type" => "string", "enum" => %w[stored_endpoint user_choice] },
        "pieces" => Shapes.list(Shapes.object({ "before" => Faces::FACE_REFERENCE, "after" => Faces::FACE_REFERENCE })),
        "retired" => Shapes.list(Faces::FACE_REFERENCE, :description => "Surface endpoints the repair retired.")
      }).freeze
      RESTORE_PARAMS = Shapes.object({
        "parent_path" => PATH.merge("description" => "The edit context holding the stamped members, as the " \
                                                     "restorable row in all gives it."),
        "zone_id" => Shapes::ID.merge("description" => "The exploded Zone's id, from that restorable row.")
      }).freeze
      RESTORE_RESULT = Shapes.object({
        "zone_id" => Shapes::ID, "member_count" => Shapes::COUNT,
        "unrecoverable" => Shapes.list({ "type" => "string" }, :description => "Zone fields Restore cannot recover.")
      }).freeze
      EXAMPLE_ZONE = { "zone_id" => "zon_Ab12Cd34Ef56", "zone_path" => [1201] }.freeze

      module_function

      def install(feature)
        SplitIdentityMenu.install(feature)
        IndependenceMenu.install(feature)
        feature.action("#{FEATURE_ID}.repair_split_face",
                       :description => "Repair copied Face identities after a native split.",
                       :refuses => Refuses::REPAIR_SPLIT_FACE,
                       :params => SPLIT_REPAIR_PARAMS, :result => SPLIT_REPAIR_RESULT,
                       :examples => [{ "zone" => EXAMPLE_ZONE, "face_id" => "fac_Mn34Op56Qr78",
                                       "zones" => [EXAMPLE_ZONE] }],
                       :undo_name => "Repair Split Face Identity",
                       :side_effects => "Reidentifies split pieces and retires invalid Surface " \
                                        "links.") do |request, proposal|
          params = request.params
          Zones.repair_split_face(request, proposal,
                                  :zone => params.fetch("zone"), :face_id => params.fetch("face_id"),
                                  :zones => params.fetch("zones"),
                                  :retaining_entity_path => params["retaining_entity_path"])
        end
        feature.action("#{FEATURE_ID}.repair_identity",
                       :description => "Give one copied Zone occurrence an identity of its own.",
                       :refuses => Refuses::REPAIR_IDENTITY,
                       :params => REPAIR_PARAMS, :result => REPAIR_RESULT, :undo_name => "Repair Zone Identity",
                       :examples => [{ "zone_path" => [1401] }],
                       :side_effects => "Reidentifies the named occurrence and its Faces; the original is " \
                                        "left untouched.") do |request, proposal|
          Zones.repair_identity(request, proposal, :zone_path => request.params.fetch("zone_path"))
        end
        install_make_independent(feature)
        feature.action("#{FEATURE_ID}.restore",
                       :description => "Regroup the stamped members of an exploded Zone, recovering only their stamp.",
                       :refuses => Refuses::RESTORE,
                       :params => RESTORE_PARAMS, :result => RESTORE_RESULT, :undo_name => "Restore Zone",
                       :examples => [{ "parent_path" => [], "zone_id" => "zon_Ab12Cd34Ef56" }],
                       :side_effects => "Groups stamped Faces in one parent context and writes a Zone " \
                                        "record.") do |request, proposal|
          Zones.restore(request, proposal, :parent_path => request.params.fetch("parent_path"),
                                           :zone_id => request.params.fetch("zone_id"))
        end
      end

      def install_make_independent(feature)
        feature.action("#{FEATURE_ID}.make_independent",
                       :description => "Give a copied Zone occurrence its own Faces and identity, leaving the " \
                                       "occurrence it shares them with untouched.",
                       :refuses => Refuses::MAKE_INDEPENDENT, :transitions => [TRANSITION],
                       :params => INDEPENDENT_PARAMS, :result => INDEPENDENT_RESULT,
                       :undo_name => "Make Zone Independent", :examples => [{ "zone_path" => [1401] }],
                       :side_effects => "Makes the occurrence's Group unique when it shares its Faces, then " \
                                        "reidentifies it and its Faces and retires their Surface " \
                                        "pairs.") do |request, proposal|
          Zones.make_independent(request, proposal, :zone_path => request.params.fetch("zone_path"),
                                                    :copy_added => request.params.fetch("copy_added", []))
        end
        feature.action(CopiedGroups::ACTION,
                       :description => "Give a plain Group copied whole, such as a storey Group holding Zones and " \
                                       "Spaces, storage of its own so its Zones and Spaces can be made independent.",
                       :refuses => %w[target.locked target.not_found target.shared_definition target.wrong_kind],
                       :params => ISOLATE_PARAMS, :result => ISOLATE_RESULT, :undo_name => "Make Copied Group Unique",
                       :examples => [{ "group_path" => [1401] }],
                       :side_effects => "Makes the Group, and any Group in it still sharing its contents, unique; " \
                                        "no record changes.") do |request, proposal|
          Zones.isolate_copied_group(request, proposal, :group_path => request.params.fetch("group_path"))
        end
      end
    end
  end
end
