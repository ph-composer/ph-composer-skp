"""For tests of Zones, Faces and Windows that rewrite a fixture's Zones: the Program sections emptied, since their
records name the fixture's own Rooms and Building Segments (context/CONTRACTS.md, "Program export")."""

from __future__ import annotations

from typing import Any

from ph_composer_translation.program_sections import (
    PROGRAM_TYPES_SECTION_ID,
    ROOMS_SECTION_ID,
    SCHEDULES_SECTION_ID,
    SET_POINTS_SECTION_ID,
    ProgramTypeSection,
    RoomProgramSection,
    ScheduleSection,
    SetPointSection,
)

PROGRAM_SECTION_IDS = (SCHEDULES_SECTION_ID, PROGRAM_TYPES_SECTION_ID, ROOMS_SECTION_ID, SET_POINTS_SECTION_ID)


def without_programs(document: dict[str, Any]) -> dict[str, Any]:
    """`document` with every Program section present and empty."""
    document["sections"].update({section: {"version": 1, "records": []} for section in PROGRAM_SECTION_IDS})
    return document


def program_sections() -> tuple[Any, ...]:
    """The four Program sections, for a test that lists its sections by hand."""
    return (ScheduleSection(), ProgramTypeSection(), RoomProgramSection(), SetPointSection())
