# frozen_string_literal: true

# One feature owns shading: the mark on a Face, Group or ComponentInstance that says its Faces shade the
# building, the actions that write and remove it, and the reads that list it. It requires Zones, whose path
# reads say which Zone holds a target; no Zones file names it (context/CONTRACTS.md, "The shading mark").
#
#   mark/           the store and record, and the one step every write goes through
#   reads.rb        pure: whether a Face is shading through a container, and the component name it exports under
#   eligibility.rb  pure: what assign and clear do to one target, context/CONTRACTS.md, "The shading mark"
#   targets.rb      the live read: a root path resolved strictly into the facts eligibility judges
#   operations.rb   assign and clear
#   selection.rb    the native selection with what each action would do
#   inventory.rb    shading.list: every mark and every shading component
#   codes.rb        the codes under the shading noun
#   declarations/   what Shading registers
require_relative "mark/schema"
require_relative "reads"
require_relative "eligibility"
require_relative "targets"
require_relative "mark/steps"
require_relative "operations"
require_relative "selection"
require_relative "inventory"
require_relative "declarations/operations"
require_relative "codes"

module PhComposer
  module Shading
    module_function

    def install(registry)
      feature = registry.feature(FEATURE_ID, :contract_version => 1, :requires => ["ph_composer.zones"])
      Registration.install(feature)
      Codes.install(feature)
    end
  end
end
