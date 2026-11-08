# frozen_string_literal: true

require_relative "approved_locations"

module PhComposer
  # The public operations over ApprovedLocations, registered as a foundation capability through the
  # same interface a feature uses. Approving needs the user: each approve command declares a standing
  # Approval, so the panel and menu open the native dialog and every other caller is refused with
  # `access.user_required`. Listing, renaming and revoking need no dialog. Results carry ids and labels,
  # never a path.
  module LocationCommands
    PREFIX = ApprovedLocations::FEATURE_ID
    SNAPSHOT = "#{PREFIX}.approved"
    APPROVALS = {
      "approve_destination" => Declarations::Approval.new(:kind => "save_file", :title => "Approve export destination",
                                                          :default_name => "export.hbjson", :standing => true).freeze,
      "approve_file" => Declarations::Approval.new(:kind => "open_file", :title => "Approve library file",
                                                   :filter => "*.json", :standing => true).freeze,
      "approve_folder" => Declarations::Approval.new(:kind => "open_folder", :title => "Approve library folder",
                                                     :standing => true).freeze
    }.freeze
    DESCRIPTIONS = {
      "approve_destination" => "Approve a save destination the user chooses in the native save dialog, so a " \
                               "caller with the export grant can export to it by location id until it is revoked.",
      "approve_file" => "Approve a library file the user chooses in a native picker, so a caller with the setup " \
                        "grant can add it once by location id.",
      "approve_folder" => "Approve a folder of library files the user chooses in a native picker, so a caller " \
                          "with the setup grant can add it once by location id."
    }.freeze
    STORE_REFUSES = %w[location.setup_unavailable location.setup_unreadable].freeze
    # What renaming or revoking one location refuses: the store's refusals and a gone or used id.
    CHANGE_REFUSES = (STORE_REFUSES + %w[location.revoked location.unknown location.used]).freeze
    MENU_LABELS = { "approve_destination" => "Approve Export Destination…", "approve_file" => "Approve Library File…",
                    "approve_folder" => "Approve Library Folder…" }.freeze
    # Where the user approves each kind of location, in the words a refusal gives an agent to pass on. An
    # export destination is approved from the Export tab too; that one offers an HBJSON name.
    WHERE = MENU_LABELS.to_h do |verb, label|
      [APPROVALS.fetch(verb).kind, "Extensions > PH-Composer > Libraries > #{label}"]
    end.freeze
    EXPORT_TAB = "the Export tab's Allow agents to export here, or "

    extend SchemaShapes

    module_function

    def install(registry)
      feature = registry.feature(PREFIX, :contract_version => Declarations::CONTRACT_VERSION)
      feature.query("#{PREFIX}.list",
                    :description => "The locations the user approved on this machine, by id and label, and " \
                                    "whether each is still there. Never carries a path or a file name.",
                    :refuses => %w[location.setup_unavailable], :params => object({}), :result => listing,
                    :examples => [{}]) do |_request|
        { "state" => ApprovedLocations.state, "locations" => ApprovedLocations.list }
      end
      feature.snapshot_section(SNAPSHOT, :query => "#{PREFIX}.list")
      install_approvals(feature)
      install_changes(feature)
    end

    def install_approvals(feature)
      examples = [{}, { "label" => "Project library" }]
      APPROVALS.each do |verb, approval|
        feature.setup_command("#{PREFIX}.#{verb}", :description => DESCRIPTIONS.fetch(verb),
                                                   :refuses => STORE_REFUSES, :approval => approval,
                                                   :params => object({ "label" => label }, :optional => ["label"]),
                                                   :result => row, :examples => examples) do |request|
          ApprovedLocations.approve(:kind => approval.kind, :path => request.approval.path,
                                    :label => request.params["label"])
        end
        install_menu(feature, verb)
      end
    end

    # The native route to an approval, beside the Libraries menu's own adds. Listing, renaming and
    # revoking are in the Libraries dialog.
    def install_menu(feature, verb)
      feature.menu_item("#{PREFIX}.#{verb}_menu", :label => MENU_LABELS.fetch(verb), :menu => "Libraries",
                                                  :available => ->(_read) { false }) do |session|
        # The dialog would only lead to the same refusal; say so before it opens.
        next session.notice(ApprovedLocations::UNREADABLE, :tone => :warning) if ApprovedLocations.state == "unreadable"

        outcome = NativeApproval.setup(menu_context(session), "#{PREFIX}.#{verb}", {})
        next if outcome["status"] == "cancelled"

        next session.notice(outcome["message"], :tone => :warning) unless outcome["status"] == "completed"

        session.notice("Approved #{outcome.dig('value', 'label')}. An agent can now use it by id.", :tone => :success)
      end
    end

    # The native menu is one client per session, as the panel is.
    def menu_context(session)
      session.feature_state(:locations_menu_context) do
        API.connect(:session_id => session.id, :capabilities => %w[read setup])
      end
    end

    def install_changes(feature)
      id = described({ "type" => "string", "minLength" => 1 }, "The location id from list or an approve command.")
      example = "location_AAAAAAAAAAAA"
      renamed = { "id" => example, "label" => "Project library" }
      feature.setup_command("#{PREFIX}.rename", :description => "Rename an approved location.",
                                                :refuses => CHANGE_REFUSES,
                                                :params => object({ "id" => id, "label" => label }), :result => row,
                                                :examples => [renamed]) do |request|
        ApprovedLocations.rename(request.params.fetch("id"), request.params.fetch("label"))
      end
      feature.setup_command("#{PREFIX}.revoke",
                            :description => "Revoke an approved location. It stays refused as location.revoked.",
                            :refuses => CHANGE_REFUSES,
                            :params => object({ "id" => id }), :result => locations,
                            :examples => [{ "id" => example }]) do |request|
        ApprovedLocations.revoke(request.params.fetch("id"))
      end
      feature.setup_command("#{PREFIX}.reset",
                            :description => "Clear this machine's approved locations when list reports them " \
                                            "unreadable. A readable store is left unchanged.",
                            :refuses => %w[location.setup_unavailable], :params => object({}), :result => locations,
                            :examples => [{}]) do |_request|
        ApprovedLocations.reset
      end
    end

    def label
      described({ "type" => "string", "minLength" => 1, "maxLength" => ApprovedLocations::LABEL_LENGTH },
                "The name the user sees for this location. Defaults to Export destination, Library file or " \
                "Library folder and a number; never the file name.")
    end

    def row
      text = { "type" => "string" }
      object({ "id" => text, "kind" => { "type" => "string", "enum" => Declarations::Approval::KINDS },
               "label" => text,
               "use" => described({ "type" => "string", "enum" => %w[reusable single] },
                                  "reusable until revoked, or single: used by one completed operation."),
               "approved_at" => text, "last_used_at" => { "type" => %w[string null] },
               "available" => described({ "type" => "boolean" }, "Whether the location is still there as approved.") })
    end

    def locations
      list(row)
    end

    def listing
      object({ "state" => described({ "type" => "string", "enum" => %w[readable unreadable] },
                                    "unreadable when the stored approvals fail to parse; approving refuses " \
                                    "until reset."),
               "locations" => locations })
    end
  end
end
