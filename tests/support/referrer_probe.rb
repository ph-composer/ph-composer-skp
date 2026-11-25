# frozen_string_literal: true

# A probe feature requiring Mechanical, standing for any other feature whose entity records name a Mechanical record: a
# record on a root Group naming one of `target_kind` under `key`, its reference target and its retargeter, which
# rewrites the record in a step of its own. A delete that routes foreign referrers through the foundation moves or
# clears it, and one that does not refuses it as reference.in_use.
module ReferrerProbe
  DICTIONARY = "ph_composer.test_referrer"
  KIND = "test.referrer.entity"

  module_function

  def install(target_kind, key)
    reference = PhComposer::Records::Reference.new(:key => key, :target_kind => target_kind, :cardinality => "one")
    entries = lambda do |model|
      model.entities.to_a.filter_map do |entity|
        text = entity.get_attribute(DICTIONARY, "record")
        text && PhComposer::Records::ReferenceEntry.new(:kind => KIND, :key => [entity.persistent_id],
                                                        :record => JSON.parse(text))
      end
    end
    target = PhComposer::Records::ReferenceTarget.new(:id => KIND, :label => "Referrer", :records => entries,
                                                      :validate => ->(_record) { [] }, :references => [reference])
    probe = Module.new
    probe.define_singleton_method(:name) { "ReferrerProbe" }
    probe.define_singleton_method(:install) do |registry|
      scope = registry.feature("test.referrer", :contract_version => 1, :requires => ["ph_composer.mechanical"])
      scope.reference_target(target)
      retarget = "test.referrer.retarget"
      scope.reference_retargeter(retarget, :target_kind => target_kind) do |request, proposal, from:, to:|
        moved = entries.call(request.model).select { |entry| entry.record[key] == from }.map do |entry|
          PhComposer::Records::ReferenceEntry.new(:kind => entry.kind, :key => entry.key,
                                                  :record => entry.record.merge(key => to))
        end
        moved.each do |entry|
          proposal.add_step(Step.new(entry.key.first, entry.record),
                            :scopes => [PhComposer::Operations::EntityScope.new([])])
        end
        PhComposer::Records::ReferencePlan.new(:entries => moved)
      end
    end
    PhComposer::Registry.install([probe])
  end

  # A root Group holding a probe record that names `id` under `key`.
  def holder(persistent_id, key, id)
    group = Sketchup::Group.new(persistent_id, Sketchup::Entities.new([]))
    group.set_attribute(DICTIONARY, "record", JSON.generate("id" => "probe_1", key => id))
    group
  end

  def named(model, persistent_id, key)
    holder = model.entities.to_a.find { |entity| entity.persistent_id == persistent_id }
    JSON.parse(holder.get_attribute(DICTIONARY, "record")).fetch(key)
  end

  # Writes one probe record on a root Group.
  class Step
    def initialize(persistent_id, record)
      @persistent_id = persistent_id
      @record = record
    end

    def apply(model, _slots)
      holder = model.entities.to_a.find { |entity| entity.persistent_id == @persistent_id }
      holder.set_attribute(DICTIONARY, "record", JSON.generate(@record))
    end

    def descriptor
      { "persistent_id" => @persistent_id, "record" => @record }
    end

    def affected
      [{ "kind" => KIND, "id" => @record.fetch("id"), "change" => "updated" }]
    end
  end
end
