# frozen_string_literal: true

module PhComposer
  # What a feature declares in its `install(registry)` (context/CONTRACTS.md, "Registration"). Each is
  # a plain value; the registry validates a feature's declarations together before any becomes
  # available.
  module Declarations
    # The contract major every declaration here belongs to. A feature declares the major it was
    # written against; an incompatible major is refused at registration.
    CONTRACT_VERSION = 1

    Feature = Struct.new(:id, :contract_version, :requires, keyword_init: true)

    # One outcome or finding code a feature raises under its own noun (context/CONTRACTS.md, "Outcomes
    # and codes"). Foundation and shared-noun codes are listed there instead.
    Code = Struct.new(:code, :owner, :description, keyword_init: true)
    # The nouns of the codes listed in context/CONTRACTS.md, which no feature may declare under.
    FOUNDATION_CODE_NOUNS = %w[access copy dependency export extension geometry identity library location object
                               operation params payload proposal query record reference registration request revision
                               runtime scope section selection session target task validation].freeze
    # Every code that table lists, so registration can check an operation's `refuses:` list against it.
    # The table stays the readable authority; tests/outcome_codes_test.rb keeps the two equal.
    FOUNDATION_CODES = %w[
      request.malformed request.unknown_operation request.api_version request.capability_denied
      request.response_too_large
      access.user_required access.revoked request.cancelled
      location.unknown location.revoked location.used location.kind_mismatch location.unavailable
      location.setup_unreadable location.setup_unavailable
      request.pending request.sequence_conflict request.outcome_unavailable request.not_received
      session.unknown session.busy session.closed session.changed session.inactive
      revision.stale proposal.changed record.unreadable proposal.foreign_write proposal.contribution_replaced
      target.not_found target.changed target.ambiguous target.locked target.wrong_kind target.wrong_hierarchy
      target.wrong_zone target.same_zone target.shared_definition target.edit_path_changed
      params.invalid validation.failed reference.invalid reference.in_use geometry.invalid geometry.failed
      geometry.split_failed
      extension.unavailable extension.schema_unsupported extension.migration_required extension.migration_failed
      extension.invalid copy.rule_missing
      query.limit_invalid query.cursor_expired
      operation.failed operation.rollback_unverified operation.participant_missing operation.proposal_required
      operation.query_missing operation.dependency_missing operation.query_cycle operation.locate_missing
      operation.participant_cycle
      identity.conflict identity.choice_required identity.choice_conflicts scope.incomplete selection.invalid
      registration.duplicate_id registration.missing_dependency registration.cycle registration.contract_major
      registration.schema_invalid
      payload.contract section.missing_dependency section.cycle section.duplicate section.version_unsupported
      object.unavailable dependency.unavailable
      export.blocked export.busy export.cancelled export.failed export.refused export.model_changed
      export.destination_changed export.replace_required export.privacy_undeclared export.relevance_unknown
      export.metadata_omitted export.user_data_passed export.revoked task.expired task.foreign
      library.adapter_invalid library.assignment_unavailable library.callback_invalid library.catalog_budget
      library.catalog_stale library.catalog_too_large library.catalog_too_many_rows library.destination_changed
      library.destination_invalid library.export_write_failed library.file_malformed library.file_too_large
      library.file_unreadable library.format_invalid library.kind_unavailable library.local_choice_required
      library.provider_ambiguous library.provider_failed library.provider_invalid
      library.provider_unavailable library.review_required library.row_semantic_invalid library.row_unavailable
      library.schema_unsupported
      library.setup_invalid library.setup_too_large library.setup_unavailable library.setup_unreadable
      library.update_destination_invalid library.update_destination_required
      runtime.asset_refused runtime.boot_timeout runtime.boot_failed runtime.translation_failed runtime.stopped
      runtime.closed runtime.unresponsive runtime.conformance_failed
    ].freeze

    # Every operation kind below declares `refuses`: the codes its handler and the dependencies it
    # calls can answer with an outcome that is not `completed`, beyond the codes every operation of its
    # kind can answer (Refusals::COMMON). `[]` says there are none beyond those.

    # A bounded read. `handler` is `->(request) { value }`; it must not write to the Model.
    # `participants` names the proposal participants the handler calls (`request.participate`); a query
    # has no proposal, so a participant it calls refuses, and the edge exists only so the declaration
    # is uniform with an action's.
    #
    # `response`, optional, says how large an answer can be: `{"bounded" => false, "prefer" => name}` marks
    # a whole-Model read, such as a panel snapshot, and names the bounded query a client with a reply
    # budget reads instead. `while_busy`, optional, marks a read of session state alone, such as the
    # Model context, that answers while a change or deferred work keeps the session busy; a read of
    # records never does.
    Query = Struct.new(:name, :owner, :description, :params, :result, :examples, :refuses, :participants, :handler,
                       :response, :while_busy, keyword_init: true)

    # A validated Model change. `handler` is `->(request, proposal) { value }`: it adds steps and record
    # writes to `proposal` (an Operations::Proposal, whose `record_changes` is the Records::ChangeSet)
    # and never writes itself. The dispatcher applies the proposal as one native operation named
    # `undo_name`. `confirmation` is the policy every client
    # must satisfy before the operation opens; only "none" is supported.
    # `participants` names the proposal participants the handler calls through `request.participate`;
    # `transitions` names the transitions it emits through `request.contribute_transition`.
    # `preconditions`, here and on the other commands, are sentences saying what a caller can prepare
    # before calling (a Zone open for editing, an approved location); the handler still checks them.
    Action = Struct.new(
      :name, :owner, :description, :params, :result, :examples, :refuses, :undo_name, :side_effects, :confirmation,
      :participants, :transitions, :handler, :preconditions, keyword_init: true
    )

    # A change to what the host shows, and nothing else, as a contribution seam. `handler` is
    # `->(request) { value }`, the same shape a query's takes, and it may change the selection, the
    # camera or the state of a shared viewport service. It writes no authored data and leaves no Undo
    # entry of its own. It may trigger the Model's own protection boundaries, such as a Volume locking
    # when the edit path leaves it; such a command says so in `side_effects` (context/AGENT_INTERFACE.md).
    #
    # It is not a query, because `context/AGENT_INTERFACE.md` says a read never changes the camera or
    # the selection. It is not an action, because an action's contract is a named native operation the
    # user can undo, and there is nothing here to undo. Both halves of that are why the seam exists:
    # before it, such a change could be reached from a native menu and from Ruby but from no client
    # (context/EXTENSIBILITY.md, "View commands").
    # `capability` is the grant it needs: `view` unless the command declares another, as a capture does.
    ViewCommand = Struct.new(:name, :owner, :description, :params, :result, :examples, :refuses, :handler,
                             :side_effects, :preconditions, :capability, keyword_init: true)

    # A file or folder location only the user can choose (context/AGENT_INTERFACE.md, "User-controlled
    # local access"). A setup command or file export that declares one runs only when a native client,
    # the panel or a menu, has asked the user through the matching dialog and passes the answer to
    # dispatch; every other caller is refused with `access.user_required` and no dialog opens. The
    # handler reads the location from `request.approval`, never from params. `kind` is one of KINDS;
    # `default_name` names a save destination and `filter` an opened file's pattern. `standing` marks a
    # command whose answer is kept as an approved location (shell/approved_locations.rb) rather than
    # used now: nothing is replaced, so no replacement question is asked.
    Approval = Struct.new(:kind, :title, :default_name, :filter, :standing, keyword_init: true) do
      def to_h
        super.compact.transform_keys(&:to_s)
      end
    end
    Approval::KINDS = %w[save_file open_file open_folder].freeze

    # A change to session or machine state that never reaches the Model: reading a configured library
    # into session memory, adding or removing a library on this machine. `handler` is
    # `->(request) { value }`, as a view command's is. It writes no record, opens no Model operation
    # and leaves no Undo entry; it is granted apart from `view`, because a view command changes only
    # what the host shows (context/EXTENSIBILITY.md, "Setup commands"). `approval` is an optional
    # Approval. `precondition` is an optional `->(request) { }` that raises a CodedError to refuse; it
    # sees the validated params and the session, never the approval, so dispatch runs it before a
    # native client opens any dialog and again before the handler.
    SetupCommand = Struct.new(:name, :owner, :description, :params, :result, :examples, :refuses, :approval,
                              :precondition, :handler, :preconditions, keyword_init: true)

    # A local file write under the explicit export grant. Its handler validates and writes the file;
    # dispatch opens no Model transaction and consumes no action sequence. A destination the user
    # chooses is declared as an Approval and stays private to the handler, outside its JSON result.
    # `precondition` is as a setup command's.
    FileExport = Struct.new(:name, :owner, :description, :params, :result, :examples, :refuses, :approval,
                            :precondition, :handler, :preconditions, keyword_init: true)

    # The kind each operation is published as, by `describe` and in Refusals::COMMON.
    OPERATION_KINDS = { Query => "query", Action => "action", ViewCommand => "view_command",
                        SetupCommand => "setup_command", FileExport => "file_export" }.freeze

    # The capability a caller needs for each kind (context/CONTRACTS.md, "Public interface"). Dispatch
    # enforces it, and `describe` and the reference publish it, from this one table. Previewing an action
    # needs only `read`.
    CAPABILITIES = { "query" => "read", "action" => "model_write", "view_command" => "view",
                     "setup_command" => "setup", "file_export" => "export" }.freeze
    PREVIEW_CAPABILITY = "read"

    # The grant `declaration` needs: its own when it declares one, else its kind's; nil for a kind no
    # client calls (a proposal participant).
    def self.capability_of(declaration, kind)
      own = declaration.respond_to?(:capability) ? declaration.capability : nil
      own || CAPABILITIES[kind]
    end

    # A panel snapshot section: the result of one registered query, under the section's name.
    SnapshotSection = Struct.new(:name, :owner, :query, :params, keyword_init: true)

    HostEventSubscription = Struct.new(:owner, :kind, :handler, keyword_init: true)

    # One section of the export extraction (context/CONTRACTS.md, "Translation sections and
    # artifacts"). `contract` is `->(reader) { [record, ...] }`: it reads through an
    # Export::RecordReader, which applies the metadata and extension-data rules, and never writes.
    # `name` is the section id the translation package reads, at `section_version`. `result` declares
    # the fields the feature's translation adds under that section id (`result[name][field]`), in
    # Export::Privacy's schema form; `report` is `->(result, display_units) { [html_section, ...] }`
    # over an Export::ResultView of them. `preflight` optionally names a registered read query
    # returning findings and explicit repair actions. `user_data_keys` are the dotted HBJSON user_data
    # keys the contributor's translation writes, such as "ph_composer.level"; the artifact guard
    # refuses any other (export/hbjson_metadata.rb). `requires` names the other contributors' sections
    # this one reads: their `projection` while collecting, through `reader.section(id)`, and their
    # result fields in its report, through `result.section(id)`. Each must belong to this feature or
    # one it requires. `projection` is an optional `->(reader) { detached value }` other contributors
    # may read.
    # `entity_projections` claims structured extension data this contributor's feature owns on another
    # feature's entities: `{"namespace", "target_kind", "source_section", "fields"}` each. The entity
    # owner's section hands over the declared fields of an understood envelope, and this contributor
    # reads them with `reader.entity_projection(namespace, target_kind)` (context/CONTRACTS.md,
    # "Records and extension data").
    ExportContributor = Struct.new(:name, :owner, :section_version, :contract, :result, :report, :preflight,
                                   :user_data_keys, :requires, :projection, :entity_projections,
                                   keyword_init: true)

    # One Colour-by mode. `projection` is `->(model) { [ColourBy::Entry, ...] }`: a pure read of the
    # feature's own entities, their world transforms and the value each one carries. `colours` is
    # `->(value) { [r, g, b] }`, nil for a value the mode cannot colour, which the service draws as
    # incomplete. `entity_kind` is open prose naming what the mode paints; the service tessellates
    # whatever entity an entry carries.
    # `sort` is an optional `->(row) { key }` over legend rows. `group` is an optional name several modes share
    # so a screen can offer them from one place (a column that shows what they colour by) without naming a
    # mode another feature owns. `stroke` is an optional width in pixels for the mode's derived lines, 1 to 10;
    # without it they draw at the overlay's outline weight.
    ColourMode = Struct.new(:name, :owner, :label, :entity_kind, :colours, :sort, :group, :stroke, :projection,
                            keyword_init: true)

    # One Colour-by readout: viewport text a feature projects, shown with any mode and with none
    # (context/EXTENSIBILITY.md, "Colour-by readouts"). `selection` says the projection reads the selection,
    # so the service rebuilds it when the selection changes.
    ColourReadout = Struct.new(:name, :owner, :label, :selection, :projection, keyword_init: true)

    # One native menu item: how a feature reaches SketchUp's own menus without `shell/` naming it.
    # `menu` is the submenu's label and items are grouped under it in registration order.
    # `handler` is `->(session) { }` and `state` an optional `->(session) { MF_CHECKED | MF_UNCHECKED }`
    # for an item that shows whether its choice is the current one. `separator_after` closes a group.
    # `available` is an optional `->(session) { true }` asked only when the viewport context menu is
    # built, so an item appears on a right-click only where it applies; `shell/` cannot decide that
    # for a feature, because deciding it means knowing what the feature's entities are.
    #
    # Native entry points delegate Model writes to registered actions. Direct handlers may only
    # change view/session state, such as starting a tool or turning a Colour-by mode on.
    # `entries` optionally supplies current per-session context-menu entries instead of one static
    # item. Contributors own catalog/selection reads; global menus do not capture dynamic catalogs.
    MenuEntry = Struct.new(:label, :handler, :state, :separator_after, keyword_init: true)
    MenuItem = Struct.new(:name, :owner, :label, :menu, :separator_after, :handler, :state, :available, :entries,
                          keyword_init: true)

    # Referring features add their rewrite steps to a definition owner's proposal and
    # return the final entity occurrences as Records::ReferencePlan.
    ReferenceRetargeter = Struct.new(:name, :owner, :target_kind, :handler, keyword_init: true)

    # A feature owning records inside another feature's entity adds its own restorable steps when
    # that owner emits `transition` (context/CONTRACTS.md, "Compound proposals"). `transition` is a
    # name the emitting feature documents; the prefix before its last segment is that feature's id.
    # `handler` is `->(request, proposal, description) { affected }`; `refuses` lists the codes it can
    # raise, which discovery adds to every action declaring that transition.
    TransitionContributor = Struct.new(:name, :owner, :transition, :refuses, :handler, keyword_init: true)

    # A step another feature composes into its own action's proposal (context/CONTRACTS.md, "Compound
    # proposals"). It is declared like an operation, with a description, params and result schemas,
    # examples and `refuses`, but no client can call it: only a handler that names it in `participants`
    # reaches it, through `request.participate`. `handler` is `->(request, proposal) { value }`; the
    # request runs under the participant's owner with an engine that writes only that owner's kinds.
    # `participants` names the participants it calls in turn.
    ProposalParticipant = Struct.new(:name, :owner, :description, :params, :result, :examples, :refuses,
                                     :participants, :handler, keyword_init: true)

    # A factory is called with the published registry and returns configured provider instances; it
    # never receives a Model or request.
    # `kinds: ["*"]` exclusively declares every registered wire kind; it cannot mix with named kinds.
    # The coordinator resolves that capability against current adapters before constructing a provider.
    LibraryProvider = Struct.new(:name, :owner, :contract_version, :kinds, :factory, keyword_init: true)

    # Pure wire methods use detached values. Local callbacks will run under this declaration's
    # owner, validating these schemas and sharing the caller's proposal; registration never runs them.
    # `display_label` is `->(mapped_values) { "text" }`, the label a catalog row, a local record and a
    # resolution candidate show; it is the only word the library service reads from a kind's values,
    # so a kind need not have a `name`. The wire schema must declare `id`, the row's identity.
    LibraryCallback = Struct.new(:params, :result, :refuses, :handler, keyword_init: true)
    LibraryAdapter = Struct.new(:wire_kind, :wire_version, :fingerprint_version, :wire_schema,
                                :mapped_schema, :fingerprint_fields,
                                :map, :reverse, :fingerprint, :display_label, :local_read, :create, :replace, :assign,
                                keyword_init: true)
    LibraryKind = Struct.new(:name, :owner, :contract_version, :record_kind, :adapter, keyword_init: true)

    # One registration problem. `subject` is the declaration it concerns; `dependency` names what it
    # needed, when that is the problem.
    Diagnostic = Struct.new(:code, :owner, :subject, :message, :dependency, keyword_init: true) do
      def to_s
        "#{code}: #{message}"
      end
    end
  end

  # A feature, or a batch of features, could not be registered. Nothing in the batch was published.
  class RegistrationError < InternalError
    attr_reader :diagnostics

    def initialize(diagnostics)
      @diagnostics = diagnostics
      super("Registration refused:\n  " + diagnostics.map(&:to_s).join("\n  "))
    end
  end
end
