"""The sections and exporters this build carries, listed by hand like the Ruby composition root.

A feature that translates adds its section here; a new exporter adds its registration. Nothing else in
the package changes. The foundation carries one section, the Model's own metadata, and no exporter.
"""

from __future__ import annotations

from typing import Any

from .constructions import ConstructionSection
from .exporters import Exporter
from .material_sources import MaterialSourcesSection
from .model_metadata import ModelMetadataSection
from .model_sections import FaceSection, ZoneSection
from .sections import Section
from .site_sections import SiteSection
from .space_sections import SpaceSection
from .thermal_bridge_sections import ThermalBridgeSection
from .window_sections import ApertureSection, WindowConstructionSection

SECTIONS: tuple[Section[Any, Any], ...] = (
    ConstructionSection(),
    MaterialSourcesSection(),
    FaceSection(),
    WindowConstructionSection(),
    ApertureSection(),
    ZoneSection(),
    SiteSection(),
    ModelMetadataSection(),
    SpaceSection(),
    ThermalBridgeSection(),
)
EXPORTERS: tuple[Exporter, ...] = ()
