# Build a library provider extension

The [example extension](../tools/examples/library_provider/) registers synthetic Materials
and tags through PH-Composer's public provider contract.

## Install the example

Copy `bldgtyp_example_library.rb` and the sibling `bldgtyp_example_library/` folder from the
example into SketchUp's Plugins folder. Enable PH-Composer, then enable BLDGTYP Example Library.
If the example reports that PH-Composer is still loading, run `BldgtypExampleLibrary.activate`
in the Ruby Console after PH-Composer starts.

## Read and copy a record

Open a synthetic model and close the panel. Load the
[walkthrough](../tools/examples/library_provider/walkthrough.rb) in the Ruby Console and run:

```ruby
proof = BldgtypExampleLibraryWalkthrough.run
raise "Example failed" unless proof.fetch("passed")
```

The script discovers the active session, loads the provider and lists its records. It previews
a Material copy, applies it with the reviewed revision and digest, then reads the local record.
It reuses a matching copy and pauses for review if the local values conflict.

Run `BldgtypExampleLibraryWalkthrough.tags` in a fresh synthetic model to copy a tag, assign it
to a holder and review replacement from a new edition. Tags use a designation as the display
label. The holder refers to a tag by typed reference.

## Adapt the example

The loader registers a `SketchupExtension`. Its feature declares dependencies on the library
foundation and the Materials owner, then calls `feature.library_provider` with a provider
factory. The provider implements `id`, `provider_kind`, `label`, `kinds`, `list(kind)` and
`freshness`. Each list returns an immutable `PhComposer::Library::Provider::Batch` with
versioned wire rows and stable library and record IDs. PH-Composer owns the copy and assignment.

See the [provider contract](../context/EXTENSIBILITY.md#library-providers-and-kind-adapters)
and [library file format](LIBRARY_FILE_FORMAT.md) for row shapes. Use the
[contract fixtures](../tests/support/library_provider_fixtures.rb) to check batch shape and immutability.
