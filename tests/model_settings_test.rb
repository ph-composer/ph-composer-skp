# frozen_string_literal: true

require_relative "test_helper"

class ModelSettingsTest < PhComposerTestCase
  DEFAULTS = { "enabled" => true, "lower" => 10.0, "upper" => 20.0 }.freeze
  VALUES = { "type" => "object", "additionalProperties" => false, "required" => DEFAULTS.keys,
             "properties" => { "enabled" => { "type" => "boolean" }, "lower" => { "type" => "number" },
                               "upper" => { "type" => "number" } } }.freeze

  def setup
    super
    @model = Sketchup.active_model
    @settings = PhComposer::ModelSettings.new(:dictionary => "ph_composer.test_settings", :defaults => DEFAULTS,
                                              :schema => VALUES, :label => "Example",
                                              :step_name => "update_example_settings",
                                              :affected => [{ "kind" => "example_settings", "id" => "test.settings",
                                                              "change" => "updated" }]) do |values|
      values.fetch("lower") < values.fetch("upper") ? [] : ["Lower must precede upper."]
    end
    settings = @settings
    feature = Module.new do
      define_singleton_method(:name) { "SettingsProbe" }
      define_singleton_method(:install) do |registry|
        scope = registry.feature("test.settings", :contract_version => 1)
        params = { "type" => "object", "additionalProperties" => false, "required" => %w[values expected_values],
                   "properties" => { "values" => VALUES, "expected_values" => VALUES } }
        scope.action("test.settings.update",
                     :description => "Update model settings.", :params => params,
                     :result => VALUES, :refuses => %w[target.changed], :undo_name => "Change Example Settings",
                     :side_effects => "Writes settings.",
                     :examples => [{ "values" => DEFAULTS, "expected_values" => DEFAULTS }]) do |request, proposal|
          settings.propose(request.model, proposal, :values => request.params.fetch("values"),
                                                    :expected_values => request.params.fetch("expected_values"))
        end
      end
    end
    PhComposer::Registry.install([feature])
    @session = PhComposer::Sessions.for(@model)
    @context = PhComposer::API.connect(:session_id => @session.id)
    @sequence = 0
  end

  def update(values, expected = @settings.read(@model))
    @sequence += 1
    PhComposer::API.invoke(:context => @context, :name => "test.settings.update",
                           :params => { "values" => values, "expected_values" => expected },
                           :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end

  def test_defaults_are_detached_and_read_without_a_dictionary_or_undo_entry
    values = @settings.read(@model)
    values["lower"] = 99
    assert_equal DEFAULTS, @settings.read(@model)
    assert_nil @settings.store.read(@model)
    assert_equal "none", update(DEFAULTS).fetch("effect")
    assert_empty @model.operations
  end

  def test_schema_and_cross_field_validation_refuse_and_poison_a_compound_proposal
    [DEFAULTS.merge("enabled" => "yes"), DEFAULTS.merge("lower" => 20)].each do |values|
      proposal = PhComposer::Operations::Proposal.new
      error = assert_raises(PhComposer::CodedError) do
        @settings.propose(@model, proposal, :values => values, :expected_values => DEFAULTS)
      end
      assert_equal "validation.failed", error.code
      assert_same error, proposal.refusal
      assert_empty proposal.steps
      assert_nil @settings.store.read(@model)
    end
  end

  def test_a_field_added_since_the_settings_were_saved_reads_its_default_and_writes_guarded
    @settings.store.write(@model, DEFAULTS.reject { |key, _| key == "upper" }.merge("lower" => 12.0))
    effective = DEFAULTS.merge("lower" => 12.0)
    assert_equal effective, @settings.read(@model)
    assert_equal "completed", update(effective.merge("upper" => 30.0), effective).fetch("status")
    assert_equal effective.merge("upper" => 30.0), @settings.read(@model)
  end

  def test_stored_settings_that_are_not_an_object_refuse_a_read_as_unreadable
    @settings.store.stub(:read, [1, 2]) do
      assert_equal "record.unreadable", assert_raises(PhComposer::CodedError) { @settings.read(@model) }.code
    end
  end

  def test_invalid_stored_settings_refuse_a_read_as_unreadable_without_the_mutation_sentence
    @settings.store.write(@model, DEFAULTS.merge("lower" => 30))
    error = assert_raises(PhComposer::CodedError) { @settings.read(@model) }
    assert_equal "record.unreadable", error.code
    refute_includes error.message, "Nothing was written."
  end

  def test_write_undo_redo_and_per_model_values_preserve_absent_storage
    after = DEFAULTS.merge("enabled" => false)
    assert_equal "committed", update(after).fetch("effect")
    assert_equal after, @settings.store.read(@model)
    assert_equal DEFAULTS, @settings.read(Sketchup::Model.new)
    @model.undo
    assert_nil @settings.store.read(@model)
    @model.redo
    assert_equal after, @settings.store.read(@model)
  end

  def test_scope_fingerprints_raw_storage_and_ignores_other_dictionaries
    scope = @settings.scope
    absent = scope.capture(@model)
    @settings.store.write(@model, DEFAULTS)
    refute scope.unchanged?(@model, absent)
    stored = scope.capture(@model)
    @model.set_attribute("ph_composer.other_settings", "record", "unrelated")
    assert scope.unchanged?(@model, stored)
    assert_equal ["ph_composer.test_settings"], scope.path
  end

  def test_stale_expected_and_apply_time_guards_refuse_without_replacing_current_values
    after = DEFAULTS.merge("lower" => 5)
    @settings.store.write(@model, after)
    assert_equal "target.changed", update(DEFAULTS, DEFAULTS).fetch("code")
    step = @settings.step(DEFAULTS, DEFAULTS.merge("upper" => 30))
    error = assert_raises(PhComposer::CodedError) { step.apply(@model, {}) }
    assert_equal "target.changed", error.code
    assert_equal after, @settings.read(@model)
    assert_equal "update_example_settings", step.descriptor.fetch("name")
    assert_equal [{ "kind" => "example_settings", "id" => "test.settings", "change" => "updated" }], step.affected
  end

  def test_failure_after_write_restores_exact_absent_or_present_raw_settings
    [nil, DEFAULTS].each do |before|
      before ? @settings.store.write(@model, before) : @settings.store.delete(@model)
      writer = @settings.store.method(:write)
      result = @settings.store.stub(:write, lambda { |model, values|
        writer.call(model, values)
        raise "Injected settings write fault"
      }) { update(DEFAULTS.merge("enabled" => false)) }
      assert_equal "rolled_back", result.fetch("effect"), result.inspect
      if before
        assert_equal before, @settings.store.read(@model)
      else
        assert_nil @settings.store.read(@model)
      end
    end
  end
end
