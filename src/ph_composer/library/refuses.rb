# frozen_string_literal: true

module PhComposer
  module Library
    # Library operations own their coordination failures. Local callback failures are declared by
    # each installed kind owner and projected for the operations that run those callbacks.
    module Refuses
      CALLBACKS = { "ph_composer.library.copy" => %i[local_read create replace assign],
                    "ph_composer.library.copy_into_proposal" => %i[local_read create replace assign],
                    "ph_composer.library.in_file" => [:local_read] }.transform_values(&:freeze).freeze

      # The version 2 provider callbacks each operation runs, keyed like CALLBACKS.
      PROVIDER_CALLBACKS = {
        "ph_composer.library.copy" => [:authorize_use], "ph_composer.library.copy_into_proposal" => [:authorize_use],
        "ph_composer.library.load" => [:begin_load], "ph_composer.library.connections.connect" => [:connect],
        "ph_composer.library.connections.disconnect" => [:disconnect],
        "ph_composer.library.connections.reauthorize" => [:reauthorize],
        "ph_composer.library.connections.settings" => [:settings],
        "ph_composer.library.connections.remove" => [:disconnect]
      }.transform_values(&:freeze).freeze

      def self.callback_codes(registry, operation_name)
        callbacks = CALLBACKS.fetch(operation_name, [])
        kinds = registry.library_kinds.values.flat_map do |kind|
          callbacks.flat_map { |part| kind.adapter[part]&.refuses || [] }
        end
        providers = PROVIDER_CALLBACKS.fetch(operation_name, [])
        kinds + registry.library_providers.values.flat_map do |declaration|
          next [] unless declaration.contract_version == 2

          providers.flat_map { |part| declaration.refuses.fetch(part, []) }
        end
      end

      PAGE = %w[query.cursor_expired query.limit_invalid].freeze
      PROVIDERS = %w[library.provider_ambiguous library.provider_failed library.provider_invalid].freeze
      LOAD = (PROVIDERS + %w[library.kind_unavailable library.provider_unavailable]).freeze
      # The load command alone also starts version 2 loads, which need a connected connection.
      LOAD_COMMAND = (LOAD + %w[library.connection_required library.reauthorization_required]).freeze
      # What a version 2 source's use check adds to a copy (Connection::Use).
      USE = %w[library.connection_changed library.model_changed library.reauthorization_required
               library.reload_required library.selection_changed library.use_expired].freeze
      CATALOG = (LOAD + PAGE + %w[library.catalog_stale]).freeze
      IN_FILE = (CATALOG + %w[library.adapter_invalid library.callback_invalid library.row_semantic_invalid
                              record.unreadable]).freeze
      COPY = (LOAD + %w[copy.rule_missing extension.invalid identity.conflict library.adapter_invalid
                        library.callback_invalid library.catalog_stale library.local_choice_required
                        library.review_required library.row_semantic_invalid
                        library.row_unavailable proposal.contribution_replaced proposal.foreign_write record.unreadable
                        reference.invalid target.ambiguous target.changed target.locked target.not_found
                        target.shared_definition target.wrong_hierarchy target.wrong_kind
                        validation.failed] + USE).uniq.freeze
      EXPORTABLE = %w[library.adapter_invalid library.catalog_too_many_rows library.kind_unavailable
                      record.unreadable target.not_found].freeze
      EXPORT_PREVIEW = (EXPORTABLE + %w[library.destination_invalid library.export_write_failed location.kind_mismatch
                                        location.revoked location.setup_unavailable location.setup_unreadable
                                        location.unavailable location.unknown location.used]).freeze
      EXPORT_FILE = (EXPORTABLE + %w[export.replace_required library.destination_changed
                                     library.destination_invalid library.export_write_failed
                                     library.file_malformed library.file_too_large library.format_invalid
                                     library.schema_unsupported library.update_destination_invalid
                                     library.update_destination_required revision.stale]).freeze
    end
  end
end
