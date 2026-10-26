# frozen_string_literal: true

require "test_helper"

class HostHelpersTest < PhComposerTestCase
  def test_state_reports_the_registered_extension_and_the_active_model_by_file_name
    model = Sketchup::Model.new
    model.path = "/private/evidence/synthetic.skp"
    Sketchup.active_model = model

    state = PhComposerHost.state

    assert_equal Sketchup.version, state.fetch("sketchup")
    extension = state.fetch("extension")
    assert_equal "ph_composer", extension.fetch("id")
    assert_equal PhComposer::VERSION, extension.fetch("version")
    assert_equal %w[PhComposer::Assemblies PhComposer::Zones PhComposer::Windows PhComposer::Spaces
                    PhComposer::ThermalBridges],
                 extension.fetch("features")
    assert_equal "synthetic.skp", state.fetch("model").fetch("file_name")
    assert_equal 0, state.fetch("model").fetch("active_path_depth")
  end
end
