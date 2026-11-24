# frozen_string_literal: true

# One feature owns hot water piping: the Pipe Type catalog, the Piping groups that hold drawn pipes and the assignment
# on each pipe, and later the tree they form and their export into the Hot Water System. It requires Mechanical,
# which owns the Hot Water System and its export, and Zones; no file of theirs, nor any other feature's, names it
# (context/EXTENSIBILITY.md, "Organization and dependencies").
#
#   type/           the Pipe Type kind, its operations and reads; names no Edge, group or run
#   group/          the Piping group record on a Group, its reference target, create, link and the occurrence rows
#   assignment/     the pipe record on an Edge, its reference target, assign, clear, the type rewrite and the selection
#   codes.rb        the `piping` noun's codes
#   declarations/   what the feature registers
module PhComposer
  module Piping
    FEATURE_ID = "ph_composer.piping"
  end
end

require_relative "codes"
require_relative "type/schema"
require_relative "type/operations"
require_relative "type/reads"
require_relative "group/schema"
require_relative "group/reference_target"
require_relative "group/steps"
require_relative "group/operations"
require_relative "assignment/schema"
require_relative "assignment/reference_target"
require_relative "assignment/steps"
require_relative "assignment/operations"
require_relative "assignment/selection"
require_relative "declarations/shapes"
require_relative "declarations/pipe_types"
require_relative "declarations/groups"
require_relative "declarations/pipes"

module PhComposer
  module Piping
    module_function

    def install(registry)
      feature = registry.feature(FEATURE_ID, :contract_version => 1,
                                             :requires => %w[ph_composer.mechanical ph_composer.zones])
      PipeTypeRegistration.install(feature)
      GroupRegistration.install(feature)
      PipeRegistration.install(feature)
      Codes.install(feature)
    end
  end
end
