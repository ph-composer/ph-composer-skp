# Licensing

PH-Composer is copyright BLDGTYP, LLC and its contributors. The code and product documentation
use the [GNU Affero General Public License, version 3 or later](../LICENSE), including the UI kit.

## Using and distributing the code

You can run and modify the extension. If you distribute a modified build, follow the license's
terms for licensing the covered work and making its Corresponding Source available. Section 13
also requires a modified version that supports remote network interaction to offer its
Corresponding Source to those remote users. Consult the license when incorporating PH-Composer
code into another program.

A library JSON file and an HBJSON export are data. For an external library service, use the
[file format](LIBRARY_FILE_FORMAT.md) or the hosted provider protocol. The
[provider contract](../context/EXTENSIBILITY.md#hosted-library-providers) describes the interface.

## Bundled components and data

The extension includes Pyodide and pinned Python wheels for HBJSON translation. See the
[third-party notices](../src/ph_composer/vendor/THIRD_PARTY_NOTICES.md) for the versions, sources
and upstream license declarations. The drawing toolbar uses [Lucide](https://lucide.dev) glyphs
under the ISC License.

The [starter library](../starter-library/README.md) is distributed separately. Its authored
records are dedicated under CC0 1.0 Universal. Linked publications retain their own terms.

## Contributing

Sign off each commit with `git commit -s` under the [Developer Certificate of Origin](DCO.md).
Submit code and data you have the right to redistribute. Use synthetic examples for project or
licensed data.
