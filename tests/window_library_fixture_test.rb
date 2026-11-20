# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/library_provider_fixtures"

class WindowLibraryFixtureTest < PhComposerTestCase
  include LibraryProviderContract

  def test_published_synthetic_file_reads_all_four_kinds_without_warnings_and_roundtrips
    declarations = PhComposer::Registry.current.library_kinds.values
    adapters = declarations.to_h { |entry| [entry.adapter.wire_kind, entry.adapter] }
                           .slice("frames", "glazings", "materials", "psi_install_types")
    provider = PhComposer::Library::FileProvider.new(
      :id => "example.file", :label => "Synthetic products",
      :path => File.expand_path("../tools/examples/library/materials.json", __dir__),
      :kinds => adapters.keys, :adapters => adapters.method(:[])
    )
    assert_equal %w[frames glazings materials psi_install_types], adapters.keys.sort
    adapters.each do |kind, adapter|
      batch = assert_library_provider(provider, kind)
      assert_empty batch.warnings, kind
      assert_empty batch.unavailable, kind
      assert_equal 1, batch.rows.length, kind
      mapped = adapter.map.call(batch.rows.first.fetch("snapshot"))
      wire = adapter.reverse.call(mapped.merge("id" => "local-synthetic"))
      assert_equal "local-synthetic", wire["id"]
      assert_equal mapped, adapter.map.call(wire)
      refute wire.key?("source")
    end
  end
end
