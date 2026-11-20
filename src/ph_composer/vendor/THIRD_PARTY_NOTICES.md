# Third-party runtime components

The bundled Pyodide 0.24.1 core embeds CPython 3.11.3. File sizes, SHA-256 hashes,
wheel versions and source URLs are recorded in `manifest.json`. The extension license
travels as `../LICENSE.txt`. Unmodified upstream license texts are under `licenses/`
and inside the wheel archives.

Pyodide's pinned repository `LICENSE` declares MPL-2.0; its `src/js/package.json`
declares Apache-2.0. Both upstream records are preserved here. This notice records
that discrepancy without declaring a new dual license. Source:
<https://github.com/pyodide/pyodide/tree/0.24.1>.
CPython's complete license history is preserved from
<https://github.com/python/cpython/blob/v3.11.3/LICENSE>.

The exact pure-Python HBJSON translation path ships these unmodified wheels. Optional
CLI, schema-validation and simulation tooling is not part of this runtime.

| Component | Version | Upstream declaration | Source |
| --- | --- | --- | --- |
| ladybug-geometry | 1.35.3 | AGPL-3.0 | [Pinned wheel](https://files.pythonhosted.org/packages/4d/7c/0aade0858e173e329eac14cf6477ad2f8bd57fe5505fce82da73251b69d5/ladybug_geometry-1.35.3-py3-none-any.whl) |
| ladybug-geometry-polyskel | 1.7.52 | AGPL-3.0 | [Pinned wheel](https://files.pythonhosted.org/packages/ea/3a/5de078edceca160fc5dc02d20a3a522bfcf5d03c4647999f852b28999c4c/ladybug_geometry_polyskel-1.7.52-py3-none-any.whl) |
| ladybug-core | 0.44.56 | AGPL-3.0 | [Pinned wheel](https://files.pythonhosted.org/packages/31/c0/b04628ffc84f9580d26d72d58d11f833380661314bcada7fc4ae55b596e2/ladybug_core-0.44.56-py3-none-any.whl) |
| honeybee-standards | 2.0.7 | GPL-3.0 (metadata classifier); MIT (bundled LICENSE) | [Pinned wheel](https://files.pythonhosted.org/packages/17/55/4a94086c7054db931527be64bb1d4ae0ec37a17867dec0671709d71a0fd7/honeybee_standards-2.0.7-py2.py3-none-any.whl) |
| honeybee-core | 1.64.65 | AGPL-3.0 | [Pinned wheel](https://files.pythonhosted.org/packages/d5/87/940c8ebe18c370d5f1e5e044f589643c9b68c9b9c1e6a52ad8f1080d9e2d/honeybee_core-1.64.65-py3-none-any.whl) |
| honeybee-energy | 1.123.23 | AGPL-3.0 | [Pinned wheel](https://files.pythonhosted.org/packages/fe/6c/0f829cd768acf43c53253d8fbd1c3f7b4498d7f7c1f009080af6d20c2907/honeybee_energy-1.123.23-py3-none-any.whl) |
| ph-units | 1.5.38 | GPL-3.0-or-later | [Pinned wheel](https://files.pythonhosted.org/packages/1e/19/ae8ecfb3de7d612f77b6c64dd80ee8f345f318fd826d831ead14c23308c8/ph_units-1.5.38-py3-none-any.whl) |
| honeybee-ph | 1.33.68 | GPL-3.0-or-later | [Pinned wheel](https://files.pythonhosted.org/packages/a1/da/1086862b01e19d0e11dfe2e4968e034b5f29b0b97d3b321448f01c60e52e/honeybee_ph-1.33.68-py3-none-any.whl) |

The honeybee-standards 2.0.7 metadata classifier says GPL-3.0, while its bundled
LICENSE contains the MIT license. The unmodified wheel and its full license text
are preserved; this notice does not erase that discrepancy. Public distribution
remains subject to its separate gate.
