# frozen_string_literal: true

module PhComposer
  # Every capability the extension offers, registered through one explicit entrypoint
  # (context/CONTRACTS.md, "Registration"). A feature is a module with `install(registry)`; the
  # composition root lists the features and calls `Registry.install`. Built-in and outside features
  # use the same calls.
  #
  #   def self.install(registry)
  #     feature = registry.feature("example.foundation", contract_version: 1)
  #     feature.record_kind(PART)
  #     feature.action("example.foundation.update_parts", description: "...", params: {...}, ...) { ... }
  #   end
  #
  # `install` only declares. Nothing is available, and no observer is attached, until the whole batch
  # validates; one problem refuses the batch and publishes nothing.
  class Registry
    ID_PATTERN = /\A[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+\z/.freeze

    attr_reader :features, :queries, :actions, :view_commands, :setup_commands, :file_exports, :record_kinds,
                :reference_targets, :extensions,
                :snapshot_sections,
                :export_contributors, :reference_retargeters, :transition_contributors, :proposal_participants,
                :library_providers, :library_kinds, :colour_modes, :colour_readouts, :menu_items, :codes,
                :subscriptions

    class << self
      def current
        @current ||= new
      end

      # Validates the features' declarations together with everything already published, then
      # publishes them, or raises RegistrationError and publishes nothing. An install started from
      # inside another (an `install` or a store that installs while it is read) is refused.
      def install(features)
        raise InternalError, "Registry.install was called while another install was running." if @installing

        begin
          @installing = true
          staged = current.stage(features)
          diagnostics = staged.diagnostics
          raise RegistrationError, diagnostics unless diagnostics.empty?

          current.publish(staged)
        ensure
          @installing = false
        end
      end

      def installed?(feature_id)
        current.features.key?(feature_id)
      end

      def reset
        raise InternalError, "Registry.reset was called while an install was running." if @installing

        current.unsubscribe_all
        @current = new
      end
    end

    def initialize
      @features = {}
      @queries = {}
      @actions = {}
      @view_commands = {}
      @setup_commands = {}
      @file_exports = {}
      @record_kinds = {}
      @reference_targets = {}
      @extensions = {}
      @snapshot_sections = {}
      @export_contributors = {}
      @reference_retargeters = {}
      @transition_contributors = {}
      @proposal_participants = {}
      @library_providers = {}
      @library_kinds = {}
      @colour_modes = {}
      @colour_readouts = {}
      @menu_items = {}
      @codes = {}
      @subscriptions = []
      @unsubscribers = []
      @owners = {}
    end

    def catalog
      Records::Catalog.new(:kinds => record_kinds.values, :extensions => extensions.values,
                           :reference_targets => reference_targets.values)
    end

    # The feature, query, action, record kind, extension or snapshot section that owns `name`.
    def owner_of(name)
      @owners[name]
    end

    # Runs each feature's `install` against a staging area and returns it with its diagnostics.
    def stage(features)
      staging = Staging.new(self)
      features.each do |feature|
        feature.install(staging)
      rescue StandardError => error
        staging.fail(feature.name, "registration.schema_invalid", "#{feature.name} could not install: #{error.message}")
      end
      staging
    end

    # Publishes a validated batch in two steps. `prepare` does everything that could fail and writes
    # nothing live; `commit` then only assigns into the maps and appends, so a batch cannot be left
    # half published. Validation has already admitted each store's dictionary and each subscription's
    # event kind, so neither `Dictionaries.register` nor `Sessions.on_host_event` can refuse here.
    def publish(staging)
      commit(staging, prepare(staging))
      self
    end

    def unsubscribe_all
      @unsubscribers.each(&:call)
      @unsubscribers = []
    end

    private

    Prepared = Struct.new(:dictionaries, :owners, keyword_init: true)

    # The batch's declarations made final, the dictionary name each kind was admitted with, and the
    # owner index, all as the registry's own frozen values.
    def prepare(staging)
      staging.declared_structs.each { |declaration| own(declaration) }
      Prepared.new(:dictionaries => staging.declared_record_kinds.map { |kind| admitted_dictionary(staging, kind) },
                   :owners => staging.owners.to_h { |name, owner| [DeepCopy.frozen(name), DeepCopy.frozen(owner)] })
    rescue StandardError => error
      raise InternalError, "Registration could not prepare the batch: #{error.class}: #{error.message}"
    end

    # The name validation admitted, so a getter that answers differently later cannot reach publishing.
    # A batch published without validation (a test's direct `publish`) is checked here instead.
    def admitted_dictionary(staging, kind)
      staging.admitted_dictionaries.fetch(kind) do
        name = kind.store.dictionary
        raise InternalError, "#{kind.id} store dictionary #{name.inspect} is not admitted." \
          unless Dictionaries.valid_name?(name)

        DeepCopy.frozen(name)
      end
    end

    def commit(staging, prepared)
      staging.declared_features.each { |feature| @features[feature.id] = feature }
      publish_each(staging.declared_queries, @queries, :name)
      publish_each(staging.declared_actions, @actions, :name)
      publish_each(staging.declared_view_commands, @view_commands, :name)
      publish_each(staging.declared_setup_commands, @setup_commands, :name)
      publish_each(staging.declared_file_exports, @file_exports, :name)
      publish_each(staging.declared_record_kinds, @record_kinds, :id)
      prepared.dictionaries.each { |name| Dictionaries.register(name) }
      publish_each(staging.declared_reference_targets, @reference_targets, :id)
      publish_each(staging.declared_extensions, @extensions, :namespace)
      publish_each(staging.declared_snapshot_sections, @snapshot_sections, :name)
      publish_each(staging.declared_export_contributors, @export_contributors, :name)
      publish_each(staging.declared_reference_retargeters, @reference_retargeters, :name)
      publish_each(staging.declared_transition_contributors, @transition_contributors, :name)
      publish_each(staging.declared_proposal_participants, @proposal_participants, :name)
      publish_each(staging.declared_library_providers, @library_providers, :name)
      publish_each(staging.declared_library_kinds, @library_kinds, :name)
      publish_each(staging.declared_colour_modes, @colour_modes, :name)
      publish_each(staging.declared_colour_readouts, @colour_readouts, :name)
      publish_each(staging.declared_menu_items, @menu_items, :name)
      publish_each(staging.declared_codes, @codes, :code)
      prepared.owners.each { |name, owner| @owners[name] = owner }
      staging.declared_subscriptions.each do |subscription|
        @subscriptions << subscription
        @unsubscribers << Sessions.on_host_event(subscription.kind, &subscription.handler)
      end
    end

    # The value members of each declaration: what validation, discovery and dispatch read. Publishing
    # replaces each with a deep-frozen copy and freezes the declaration, so neither a builder the
    # contributor kept nor anything a reader is handed can change a published declaration. Every other
    # member is behaviour (a handler, validator, factory, projection or callback) and is kept by
    # identity, never copied or frozen. The record classes (core/records) detach their own values when
    # they are built.
    VALUE_MEMBERS = {
      Declarations::Feature => %i[id contract_version requires],
      Declarations::Query => %i[name owner description params result examples refuses participants response
                                while_busy],
      Declarations::Action => %i[name owner description params result examples refuses undo_name side_effects
                                 confirmation participants transitions preconditions],
      Declarations::ViewCommand => %i[name owner description params result examples refuses side_effects
                                      preconditions],
      Declarations::SetupCommand => %i[name owner description params result examples refuses preconditions],
      Declarations::FileExport => %i[name owner description params result examples refuses preconditions],
      Declarations::SnapshotSection => %i[name owner query params],
      Declarations::ExportContributor => %i[name owner section_version result preflight user_data_keys requires
                                            entity_projections],
      Declarations::ColourMode => %i[name owner label entity_kind group stroke],
      Declarations::ColourReadout => %i[name owner label selection],
      Declarations::MenuItem => %i[name owner label menu separator_after],
      Declarations::ReferenceRetargeter => %i[name owner target_kind],
      Declarations::TransitionContributor => %i[name owner transition refuses],
      Declarations::ProposalParticipant => %i[name owner description params result examples refuses participants],
      Declarations::LibraryProvider => %i[name owner contract_version kinds],
      Declarations::LibraryKind => %i[name owner contract_version record_kind],
      Declarations::HostEventSubscription => %i[owner kind],
      Declarations::Code => %i[code owner description]
    }.freeze
    LIBRARY_ADAPTER_VALUES = %i[wire_kind wire_version fingerprint_version wire_schema mapped_schema
                                fingerprint_fields].freeze
    LIBRARY_CALLBACK_VALUES = %i[params result refuses].freeze
    LIBRARY_CALLBACKS = %i[local_read create replace assign].freeze

    def own(declaration)
      return declaration if declaration.frozen?

      owned_values(declaration, VALUE_MEMBERS.fetch(declaration.class))
      declaration.approval = owned_approval(declaration.approval) if declaration.respond_to?(:approval=)
      declaration.adapter = owned_adapter(declaration.adapter) if declaration.is_a?(Declarations::LibraryKind)
      declaration.freeze
    end

    def owned_values(struct, members)
      members.each { |member| struct[member] = DeepCopy.frozen(struct[member]) unless struct[member].nil? }
      struct
    end

    def owned_approval(approval)
      approval && owned_values(approval.dup, Declarations::Approval.members).freeze
    end

    # The adapter struct is the contributor's, so it is copied; its methods and callback handlers are
    # behaviour and are kept.
    def owned_adapter(adapter)
      return adapter unless adapter.is_a?(Declarations::LibraryAdapter)

      adapter = owned_values(adapter.dup, LIBRARY_ADAPTER_VALUES)
      LIBRARY_CALLBACKS.each do |method|
        callback = adapter[method]
        adapter[method] = owned_values(callback.dup, LIBRARY_CALLBACK_VALUES).freeze if callback
      end
      adapter.freeze
    end

    def publish_each(declarations, target, key)
      declarations.each { |declaration| target[declaration.public_send(key)] = declaration }
    end

    # Collects one batch's declarations and checks them against each other and the live registry.
    class Staging
      attr_reader :declared_features, :declared_queries, :declared_actions, :declared_view_commands,
                  :declared_setup_commands, :declared_file_exports,
                  :declared_record_kinds, :declared_reference_targets, :declared_extensions,
                  :declared_snapshot_sections,
                  :declared_export_contributors, :declared_reference_retargeters,
                  :declared_transition_contributors, :declared_proposal_participants,
                  :declared_library_providers, :declared_library_kinds,
                  :declared_colour_modes, :declared_colour_readouts,
                  :declared_menu_items, :declared_codes,
                  :declared_subscriptions, :owners, :named, :admitted_dictionaries

      def initialize(live)
        @live = live
        @declared_features = []
        @declared_queries = []
        @declared_actions = []
        @declared_view_commands = []
        @declared_setup_commands = []
        @declared_file_exports = []
        @declared_record_kinds = []
        @declared_reference_targets = []
        @declared_extensions = []
        @declared_snapshot_sections = []
        @declared_export_contributors = []
        @declared_reference_retargeters = []
        @declared_transition_contributors = []
        @declared_proposal_participants = []
        @declared_library_providers = []
        @declared_library_kinds = []
        @declared_colour_modes = []
        @declared_colour_readouts = []
        @declared_menu_items = []
        @declared_codes = []
        @declared_subscriptions = []
        @owners = {}
        @named = []
        @failures = []
        @admitted_dictionaries = {}.compare_by_identity
      end

      # Contribution schemas may reuse a dependency's published record shape during registration.
      # Same-batch declarations take precedence; already installed dependencies remain visible.
      def record_descriptor(kind_id)
        declared = declared_record_kinds.find { |kind| kind.id == kind_id } ||
                   declared_reference_targets.find { |target| target.id == kind_id }
        declared ? declared.descriptor : @live.catalog.descriptor(kind_id)
      end

      # Declares a feature and returns the scope its other declarations are made through.
      def feature(id, contract_version:, requires: [])
        declaration = Declarations::Feature.new(:id => id, :contract_version => contract_version,
                                                :requires => requires)
        @declared_features << declaration
        FeatureScope.new(self, declaration)
      end

      # The owner of a name declared in this batch, or else already published.
      def owner_of(name)
        owners[name] || @live.owner_of(name)
      end

      def fail(owner, code, message)
        @failures << Declarations::Diagnostic.new(:code => code, :owner => owner.to_s, :subject => owner.to_s,
                                                  :message => message)
      end

      def add(collection, owner, name, declaration)
        public_send(collection) << declaration
        @named << [owner, name]
        @owners[name] ||= owner
      end

      def diagnostics
        Validation.new(@live, self).diagnostics + @failures
      end

      # Every declaration struct the batch made, which publishing takes ownership of.
      def declared_structs
        declared_features + declared_operations + declared_snapshot_sections + declared_export_contributors +
          declared_reference_retargeters + declared_transition_contributors + declared_proposal_participants +
          declared_library_providers + declared_library_kinds + declared_colour_modes + declared_colour_readouts +
          declared_menu_items + declared_codes + declared_subscriptions
      end

      # Every operation the batch declared, of every kind a client can call.
      def declared_operations
        declared_queries + declared_actions + declared_view_commands + declared_setup_commands + declared_file_exports
      end
    end

    # The declarations one feature makes. Every name it declares must sit under the feature's id.
    class FeatureScope
      attr_reader :id

      def initialize(staging, feature)
        @staging = staging
        @feature = feature
        @id = feature.id
      end

      def record_kind(kind)
        @staging.add(:declared_record_kinds, id, kind.id, kind)
      end

      def reference_target(target)
        @staging.add(:declared_reference_targets, id, target.id, target)
      end

      def extension(extension)
        @staging.add(:declared_extensions, id, extension.namespace, extension)
      end

      # Every operation names `refuses:`. It defaults to nil only so validation can name each operation
      # that omits it, rather than one Ruby error ending the feature's install.
      def query(name, description:, params:, result:, refuses: nil, examples: [], participants: [], response: nil,
                while_busy: false, &handler)
        declaration = Declarations::Query.new(
          :name => name, :owner => id, :description => description, :params => params, :result => result,
          :examples => examples, :refuses => refuses, :participants => participants, :handler => handler,
          :response => response, :while_busy => while_busy
        )
        @staging.add(:declared_queries, id, name, declaration)
      end

      def action(name, description:, params:, result:, undo_name:, side_effects:, examples: [],
                 refuses: nil, confirmation: "none", participants: [], transitions: [], preconditions: [], &handler)
        declaration = Declarations::Action.new(
          :name => name, :owner => id, :description => description, :params => params, :result => result,
          :examples => examples, :refuses => refuses, :undo_name => undo_name, :side_effects => side_effects,
          :confirmation => confirmation, :participants => participants, :transitions => transitions,
          :handler => handler, :preconditions => preconditions
        )
        @staging.add(:declared_actions, id, name, declaration)
      end

      # One viewport-state command: it changes what the host shows and never the Model, so it takes
      # no `undo_name` and no sequence number. A handler that would write a record wants `action`.
      def view_command(name, description:, params:, result:, refuses: nil, examples: [], side_effects: nil,
                       preconditions: [], capability: "view", &handler)
        unless CallerRegistry::CAPABILITIES.include?(capability)
          raise ArgumentError, "#{name} names an unknown capability #{capability.inspect}."
        end

        declaration = Declarations::ViewCommand.new(
          :name => name, :owner => id, :description => description, :params => params, :result => result,
          :examples => examples, :refuses => refuses, :handler => handler, :side_effects => side_effects,
          :preconditions => preconditions, :capability => capability
        )
        @staging.add(:declared_view_commands, id, name, declaration)
      end

      # One session- or machine-state command: it never touches the Model, so it takes no `undo_name`
      # and no sequence number, and it changes nothing the viewport shows unless a refresh follows.
      def setup_command(name, description:, params:, result:, refuses: nil, examples: [], approval: nil,
                        precondition: nil, preconditions: [], &handler)
        declaration = Declarations::SetupCommand.new(
          :name => name, :owner => id, :description => description,
          :params => ApprovedLocations.with_param(params, approval), :result => result,
          :examples => examples, :refuses => refuses, :approval => approval, :precondition => precondition,
          :handler => handler, :preconditions => preconditions
        )
        @staging.add(:declared_setup_commands, id, name, declaration)
      end

      def snapshot_section(name, query:, params: {})
        declaration = Declarations::SnapshotSection.new(:name => name, :owner => id, :query => query, :params => params)
        @staging.add(:declared_snapshot_sections, id, name, declaration)
      end

      def file_export(name, description:, params:, result:, refuses: nil, examples: [], approval: nil,
                      precondition: nil, preconditions: [], &handler)
        declaration = Declarations::FileExport.new(
          :name => name, :owner => id, :description => description,
          :params => ApprovedLocations.with_param(params, approval), :result => result,
          :examples => examples, :refuses => refuses, :approval => approval, :precondition => precondition,
          :handler => handler, :preconditions => preconditions
        )
        @staging.add(:declared_file_exports, id, name, declaration)
      end

      # Adds a section to the export extraction and declares the result fields its translation adds.
      def export_contributor(name, section_version:, result: {}, report: nil, preflight: nil, user_data_keys: [],
                             requires: [], projection: nil, entity_projections: [], &contract)
        declaration = Declarations::ExportContributor.new(
          :name => name, :owner => id, :section_version => section_version, :contract => contract,
          :result => result, :report => report, :preflight => preflight,
          :user_data_keys => user_data_keys, :requires => requires, :projection => projection,
          :entity_projections => entity_projections
        )
        @staging.add(:declared_export_contributors, id, name, declaration)
      end

      # One Colour-by mode. The projection receives a read request: it reads this feature's entities,
      # and another feature's values only through `read.query` of a declared dependency. `stroke` widens
      # the mode's derived lines.
      def colour_mode(name, label:, entity_kind:, colours:, sort: nil, group: nil, stroke: nil, &projection)
        declaration = Declarations::ColourMode.new(
          :name => name, :owner => id, :label => label, :entity_kind => entity_kind, :colours => colours,
          :sort => sort, :group => group, :stroke => stroke, :projection => projection
        )
        @staging.add(:declared_colour_modes, id, name, declaration)
      end

      # One Colour-by readout: a pure projection returning ColourBy::Readout text for the viewport, on or
      # off per Model session and shown with any mode or none. `selection: true` gives the projection
      # `read.selection` and rebuilds it when the selection changes.
      def colour_readout(name, label:, selection: false, &projection)
        declaration = Declarations::ColourReadout.new(:name => name, :owner => id, :label => label,
                                                      :selection => selection, :projection => projection)
        @staging.add(:declared_colour_readouts, id, name, declaration)
      end

      # One native menu item under the named submenu. The handler receives the current ModelSession.
      def menu_item(name, label:, menu:, separator_after: false, state: nil, available: nil, &handler)
        declaration = Declarations::MenuItem.new(
          :name => name, :owner => id, :label => label, :menu => menu,
          :separator_after => separator_after, :state => state, :available => available, :handler => handler
        )
        @staging.add(:declared_menu_items, id, name, declaration)
      end

      # Current context-menu entries supplied when it opens, rather than a catalog snapshot captured
      # at extension install. The provider returns Declarations::MenuEntry values for this session.
      def menu_entries(name, menu:, available: nil, &entries)
        declaration = Declarations::MenuItem.new(:name => name, :owner => id, :menu => menu,
                                                 :available => available, :entries => entries)
        @staging.add(:declared_menu_items, id, name, declaration)
      end

      def reference_retargeter(name, target_kind:, &handler)
        declaration = Declarations::ReferenceRetargeter.new(:name => name, :owner => id,
                                                            :target_kind => target_kind, :handler => handler)
        @staging.add(:declared_reference_retargeters, id, name, declaration)
      end

      # Runs when the feature that owns `transition` emits it (HandlerRequest#contribute_transition).
      def transition_contributor(name, transition:, refuses: [], &handler)
        declaration = Declarations::TransitionContributor.new(:name => name, :owner => id, :transition => transition,
                                                              :refuses => refuses, :handler => handler)
        @staging.add(:declared_transition_contributors, id, name, declaration)
      end

      # A participant is declared as an operation is; `participants` names the ones its handler calls.
      def proposal_participant(name, description:, params:, result:, refuses: nil, examples: [], participants: [],
                               &handler)
        declaration = Declarations::ProposalParticipant.new(
          :name => name, :owner => id, :description => description, :params => params, :result => result,
          :examples => examples, :refuses => refuses, :participants => participants, :handler => handler
        )
        @staging.add(:declared_proposal_participants, id, name, declaration)
      end

      def library_provider(name, contract_version:, kinds:, &factory)
        declaration = Declarations::LibraryProvider.new(:name => name, :owner => id,
                                                        :contract_version => contract_version, :kinds => kinds,
                                                        :factory => factory)
        @staging.add(:declared_library_providers, id, name, declaration)
      end

      def library_kind(name, contract_version:, record_kind:, adapter:)
        declaration = Declarations::LibraryKind.new(:name => name, :owner => id,
                                                    :contract_version => contract_version, :record_kind => record_kind,
                                                    :adapter => adapter)
        @staging.add(:declared_library_kinds, id, name, declaration)
      end

      # Declares one code this feature raises under its own noun, such as `window.unhosted`. Codes are not
      # names under the feature id; one feature owns each noun.
      def code(code, description:)
        @staging.declared_codes << Declarations::Code.new(:code => code, :owner => id, :description => description)
      end

      # Subscribes to a session host event once the batch publishes (session/sessions.rb HOST_EVENTS).
      def on_host_event(kind, &handler)
        @staging.declared_subscriptions << Declarations::HostEventSubscription.new(:owner => id, :kind => kind,
                                                                                   :handler => handler)
      end
    end
  end
end
