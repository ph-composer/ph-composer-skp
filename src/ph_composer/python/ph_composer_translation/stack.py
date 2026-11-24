"""The one place the package imports honeybee, ladybug or PHX.

Nothing is imported when a module of this package is imported: every module must import without the
stack (tests/python/test_imports.py), so the contract layer runs under pytest alone and nothing runs
before the runtime has installed the wheels. A section calls `load` inside `translate`.

The export runtime installs its pinned wheels on demand. A missing requested package raises
`StackUnavailable` and names the module; no external resolver or system-Python fallback runs.
"""

from __future__ import annotations

import importlib
from types import ModuleType

#: The top-level packages this seam serves. Anything else is imported where it is used.
PACKAGES = frozenset(
    {
        "honeybee",
        "honeybee_energy",
        "honeybee_ph",
        "honeybee_phhvac",
        "honeybee_energy_ph",
        "ladybug",
        "ladybug_geometry",
        "PHX",
    }
)


class StackUnavailable(Exception):
    """The runtime does not carry the requested package."""


def load(module: str) -> ModuleType:
    """`load("honeybee.model")` imports and returns that module, on first use."""
    if module.split(".")[0] not in PACKAGES:
        raise ValueError(f"{module} is not served by the stack seam")
    try:
        return importlib.import_module(module)
    except ImportError as error:
        raise StackUnavailable(f"{module} is not installed in this runtime") from error
