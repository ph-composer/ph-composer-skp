"""Authored opaque constructions, with mixed layers and membranes carried without approximation."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import Any

from . import stack
from .contract import JSONValue, RecordError, with_user_data
from .contract.assembly_records import AssemblyRecord, LayerRecord, MaterialRecord
from .result import Finding
from .sections import Inputs, Requirement, Section

CONSTRUCTION_SECTION_ID = "ph_composer.assemblies.export.constructions"
DEFAULT_DENSITY = 600.0
DEFAULT_SPECIFIC_HEAT = 1000.0


@dataclass(frozen=True)
class TranslatedConstruction:
    source: AssemblyRecord
    construction: Any
    defaulted_material_ids: tuple[str, ...]
    membrane_names: tuple[str, ...]
    # The same layers innermost first, for the counterpart of a Surface pair that names this Assembly
    # reversed: honeybee needs the two sides of one interior element to hold mirrored layers.
    reversed_construction: Any = None


CONSTRUCTIONS = Requirement(CONSTRUCTION_SECTION_ID, TranslatedConstruction)


class ConstructionSection(Section[AssemblyRecord, TranslatedConstruction]):
    id = CONSTRUCTION_SECTION_ID
    versions = frozenset({1})
    object_type = TranslatedConstruction
    # A definition costs its own object only. An assigned Face's Zone requires that object and blocks.
    required_for_export = False

    def read(self, raw: Mapping[str, object]) -> AssemblyRecord:
        return AssemblyRecord.read(raw)

    def translate(self, record: AssemblyRecord, inputs: Inputs) -> TranslatedConstruction:
        stack.load("honeybee_energy._extend_honeybee")
        stack.load("honeybee_ph")
        thermal: list[Any] = []
        membranes: list[dict[str, Any]] = []
        defaulted: set[str] = set()
        for index, layer in enumerate(record.layers):
            material = record.materials[layer.segments[0].material_id]
            if material.category == "membrane":
                membranes.append(
                    {
                        "outside_index": index,
                        "layer_id": layer.id,
                        "segment_id": layer.segments[0].id,
                        "thickness_mm": layer.thickness_mm,
                        "material": _membrane(material),
                    }
                )
                continue
            for segment in layer.segments:
                used = record.materials[segment.material_id]
                if used.density_kg_m3 is None or used.specific_heat_j_kgk is None:
                    defaulted.add(used.id)
            try:
                thermal.append(_layer(record, layer))
            except (AssertionError, ValueError) as error:
                raise RecordError(f"assembly {record.id} Layer {layer.id} could not be built: {error}") from error
        try:
            construction = stack.load("honeybee_energy.construction.opaque").OpaqueConstruction(
                f"ph_composer_{record.id}", thermal
            )
        except (AssertionError, ValueError) as error:
            raise RecordError(f"assembly {record.id} could not be built: {error}") from error
        construction.display_name = record.name
        construction.user_data = with_user_data(
            {"ph_composer": {"assembly_id": record.id, "membrane_layers": membranes}}, record.user_data
        )
        return TranslatedConstruction(
            record,
            construction,
            tuple(sorted(defaulted)),
            tuple(dict.fromkeys(row["material"]["name"] for row in membranes)),
            _reversed(record, construction, membranes),
        )

    def findings(self, objects: Mapping[str, TranslatedConstruction]) -> Sequence[Finding]:
        return [
            Finding(
                "material.thermal_mass_defaulted",
                self.id,
                identifier,
                "Missing thermal mass properties use 600 kg/m3 density and 1000 J/kgK specific heat "
                "for Materials "
                + ", ".join(f'"{value.source.materials[id].name}"' for id in value.defaulted_material_ids)
                + f' in Assembly "{value.source.name}".',
                False,
            )
            for identifier, value in objects.items()
            if value.defaulted_material_ids
        ]

    def result_fields(self, objects: Mapping[str, TranslatedConstruction]) -> Mapping[str, JSONValue]:
        return {
            "construction_definitions": [
                {
                    "assembly_id": identifier,
                    "name": value.source.name,
                    "thermal_layer_count": len(value.construction.materials),
                    "membrane_names": list(value.membrane_names),
                    "defaulted_material_ids": list(value.defaulted_material_ids),
                }
                for identifier, value in objects.items()
            ]
        }


def _energy(material: MaterialRecord, thickness: float, identifier: str) -> Any:
    result = stack.load("honeybee_energy.material.opaque").EnergyMaterial(
        identifier,
        thickness,
        material.conductivity_w_mk,
        material.density_kg_m3 if material.density_kg_m3 is not None else DEFAULT_DENSITY,
        material.specific_heat_j_kgk if material.specific_heat_j_kgk is not None else DEFAULT_SPECIFIC_HEAT,
        thermal_absorptance=material.emissivity if material.emissivity is not None else 0.9,
    )
    result.display_name = material.name
    if material.color:
        rgb = [int(material.color[index : index + 2], 16) for index in (1, 3, 5)]
        result.properties.ph.ph_color = stack.load("honeybee_energy_ph.properties.materials.opaque").PhColor.from_rgb(
            *rgb
        )
    return result


def _layer(assembly: AssemblyRecord, layer: LayerRecord) -> Any:
    prefix = f"ph_composer_{assembly.id}_{layer.id}"
    if len(layer.segments) == 1 and layer.segments[0].steel_stud_spacing_mm is None:
        return _energy(assembly.materials[layer.segments[0].material_id], layer.thickness_mm / 1000, prefix)
    cells = [
        _energy(assembly.materials[segment.material_id], layer.thickness_mm / 1000, f"{prefix}_s{index + 1}")
        for index, segment in enumerate(layer.segments)
    ]
    grid = stack.load("honeybee_energy_ph.properties.materials.opaque").PhDivisionGrid()
    grid.set_row_heights([1.0])
    grid.set_column_widths([segment.width_mm / 1000 for segment in layer.segments])
    grid.steel_stud_spacing_mm = next(
        (segment.steel_stud_spacing_mm for segment in layer.segments if segment.steel_stud_spacing_mm is not None), None
    )
    for column, material in enumerate(cells):
        grid.set_cell_material(column, 0, material)
    base = grid.get_base_material()
    host = base.duplicate()
    host.identifier = f"{prefix}_hybrid"
    host.display_name = " + ".join(dict.fromkeys(material.display_name for material in cells))
    host.conductivity = grid.get_equivalent_conductivity()
    host.properties.ph.divisions = grid
    host.properties.ph.ph_color = base.properties.ph.ph_color
    return host


def _reversed(record: AssemblyRecord, construction: Any, membranes: list[dict[str, Any]]) -> Any:
    """The construction seen from the other side: the same material objects in the opposite order, so
    honeybee's reversed-layer check on a Surface pair compares equal identities."""
    last = len(record.layers) - 1
    reversed_construction = stack.load("honeybee_energy.construction.opaque").OpaqueConstruction(
        f"{construction.identifier}_reversed", list(reversed(construction.materials))
    )
    reversed_construction.display_name = f"{record.name} (reversed)"
    reversed_construction.user_data = with_user_data(
        {
            "ph_composer": {
                "assembly_id": record.id,
                "membrane_layers": [{**row, "outside_index": last - row["outside_index"]} for row in membranes],
            }
        },
        record.user_data,
    )
    return reversed_construction


def _membrane(material: MaterialRecord) -> dict[str, JSONValue]:
    return {
        "project_material_id": material.id,
        "name": material.name,
        "category": material.category,
        "color": material.color,
        "density_kg_m3": material.density_kg_m3,
        "specific_heat_j_kgk": material.specific_heat_j_kgk,
        "emissivity": material.emissivity,
    }
