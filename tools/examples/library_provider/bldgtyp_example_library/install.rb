# frozen_string_literal: true

# This extension never loads or edits PH-Composer's files. Enable it after PH-Composer has composed.
module BldgtypExampleLibrary
  FEATURE_ID = "bldgtyp.example_library"
  PROVIDER_KIND = "#{FEATURE_ID}.synthetic"
  TAG = "#{FEATURE_ID}.tag"
  HOLDER = "#{FEATURE_ID}.holder"

  class Provider
    def id; "#{FEATURE_ID}.materials"; end
    def provider_kind; PROVIDER_KIND; end
    def label; "BLDGTYP synthetic example"; end
    def kinds; %w[materials tags].freeze; end
    def freshness; { "version" => "1" }.freeze; end

    # The tag edition the provider serves; the walkthrough raises it to show a reviewed replacement.
    class << self
      attr_writer :edition

      def edition
        @edition || 1
      end
    end

    def list(kind)
      unless kinds.include?(kind)
        raise PhComposer::Library::Error.new("library.kind_unavailable", "The example serves Materials and tags only.")
      end
      return tags if kind == "tags"

      rows = [["insulation", "Example synthetic insulation", 0.04],
              ["finish", "Example synthetic finish", 0.2]].map do |id, name, conductivity|
        snapshot = { "id" => id, "name" => name, "category" => id == "insulation" ? "insulation" : "finishes",
                     "color" => "#ffffff",
                     "conductivity_w_mk" => conductivity, "density_kg_m3" => nil, "specific_heat_j_kgk" => nil,
                     "emissivity" => nil, "notes" => "Synthetic example. Not a product specification.",
                     "datasheet_links" => [] }
        { "library_id" => "bldgtyp.example.synthetic", "library_name" => label,
          "record_id" => id, "wire_schema_version" => 1, "snapshot" => snapshot }
      end
      batch(rows)
    end

    # A kind with no `name`: rows carry a wire id, a designation and a height.
    def tags
      batch([["north", "N-1"], ["south", "S-1"]].map do |id, designation|
        { "library_id" => "bldgtyp.example.synthetic", "library_name" => label, "record_id" => id,
          "wire_schema_version" => 1,
          "snapshot" => { "id" => id, "designation" => designation, "height_mm" => 100.0 * self.class.edition } }
      end)
    end

    def batch(rows)
      PhComposer::Library::Provider::Batch.new(:rows => rows, :warnings => [], :unavailable => [],
                                               :freshness => freshness)
    end
  end

  # The example's own name-free definition, and a local holder that names one by typed reference.
  # PhComposer is named only inside methods: this file must load, and refuse, before the core has.
  module Tags
    OBJECT = { "type" => "object" }.freeze
    VALUES = { "designation" => { "type" => "string", "minLength" => 1 },
               "height_mm" => { "type" => "number", "exclusiveMinimum" => 0, "x-unit" => "mm" } }.freeze
    MAPPED = { "type" => "object", "required" => VALUES.keys, "additionalProperties" => false,
               "properties" => VALUES }.freeze

    module_function

    def kinds
      records = PhComposer::Records
      tag = records::RecordKind.new(
        :id => TAG, :label => "Example tag", :schema_version => 1, :id_prefix => "btg",
        :fields => VALUES.map { |key, schema| records::Field.new(:key => key, :schema => schema, :required => true) } +
                   [records::Field.new(:key => "source", :schema => records::AuthoringFields.source_schema)]
      )
      holder = records::RecordKind.new(
        :id => HOLDER, :label => "Example tag holder", :schema_version => 1, :id_prefix => "bth",
        :fields => [records::Field.new(:key => "position", :schema => { "type" => "string", "minLength" => 1 },
                                       :required => true),
                    records::Reference.new(:key => "tag_id", :target_kind => TAG, :cardinality => "one")]
      )
      [tag, holder]
    end

    def callback(params, result = OBJECT, examples: nil, &handler)
      PhComposer::Declarations::LibraryCallback.new(:params => params, :result => result, :refuses => [],
                                                    :handler => handler, :examples => examples)
    end

    def edit(properties)
      { "type" => "object", "required" => properties.keys, "properties" => properties }
    end

    def adapter
      wire = MAPPED.merge("required" => ["id"] + VALUES.keys,
                          "properties" => VALUES.merge("id" => { "type" => "string", "minLength" => 1 }))
      PhComposer::Declarations::LibraryAdapter.new(
        :wire_kind => "tags", :wire_version => 1, :fingerprint_version => 1, :wire_schema => wire,
        :mapped_schema => MAPPED, :fingerprint_fields => VALUES.keys,
        :display_label => ->(mapped) { mapped.fetch("designation") },
        :map => ->(row) { row.slice(*VALUES.keys) }, :reverse => ->(row) { row.slice("id", *VALUES.keys) },
        :fingerprint => ->(row) { PhComposer::CanonicalJson.digest(row.slice(*VALUES.keys)) },
        :local_read => callback(OBJECT, { "type" => "array", "items" => OBJECT }) do |request, _proposal|
          request.engine.ids(TAG).map do |id|
            record = request.engine.find(TAG, id)
            { "id" => id, "mapped" => record.slice(*VALUES.keys), "expected_values" => record.slice(*VALUES.keys),
              "source" => record["source"] }
          end
        end,
        :create => callback(edit("values" => OBJECT)) do |request, proposal|
          { "id" => request.engine.propose_create(TAG, proposal, :values => request.params.fetch("values")) }
        end,
        :replace => callback(edit("id" => { "type" => "string" }, "values" => OBJECT,
                                  "expected_values" => OBJECT)) do |request, proposal|
          id = request.params.fetch("id")
          request.engine.propose_update(TAG, id, proposal, :values => request.params.fetch("values"),
                                                           :expected_values => request.params.fetch("expected_values"))
          { "id" => id }
        end,
        # The assignment target is one holder; assigning names the copied tag on it. The example is what
        # `describe` publishes as the kind's assignment example.
        :assign => callback(edit("target" => edit("id" => { "type" => "string" }),
                                 "local_id" => { "type" => "string" }),
                            :examples => [{ "target" => { "id" => "bth_Ab12Cd34Ef56" },
                                            "local_id" => "btg_Ab12Cd34Ef56" }]) do |request, proposal|
          id = request.params.fetch("target").fetch("id")
          tag = request.params.fetch("local_id")
          request.engine.propose_update(HOLDER, id, proposal, :values => { "tag_id" => tag })
          { "id" => id }
        end
      )
    end

    def install(feature)
      kinds.each { |kind| feature.record_kind(kind) }
      feature.library_kind("#{FEATURE_ID}.tags", :contract_version => 1, :record_kind => TAG, :adapter => adapter)
      feature.action("#{FEATURE_ID}.add_holder",
                     :description => "Add one example tag holder at a position.",
                     :params => edit("position" => { "type" => "string", "minLength" => 1 }),
                     :result => OBJECT, :refuses => %w[validation.failed], :undo_name => "Add Example Tag Holder",
                     :side_effects => "Creates one record.",
                     :examples => [{ "position" => "North wall" }]) do |request, proposal|
        { "id" => request.engine.propose_create(HOLDER, proposal, :values => request.params) }
      end
    end
  end

  module_function

  def install(registry)
    feature = registry.feature(FEATURE_ID, :contract_version => 1,
                                           :requires => %w[ph_composer.library ph_composer.assemblies])
    feature.library_provider(PROVIDER_KIND, :contract_version => 1, :kinds => %w[materials tags]) { [Provider.new] }
    Tags.install(feature)
  end

  def activate
    unless defined?(PhComposer::Registry) &&
           %w[ph_composer.library ph_composer.assemblies].all? { |id| PhComposer::Registry.installed?(id) }
      warn "BLDGTYP Example Library: enable this extension after PH-Composer has finished loading. Nothing registered."
      return false
    end
    PhComposer::Registry.install([self])
    true
  rescue PhComposer::RegistrationError
    warn "BLDGTYP Example Library: registration refused. Check duplicate names and supported contract versions."
    false
  end
end

BldgtypExampleLibrary.activate
