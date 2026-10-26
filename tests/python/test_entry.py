"""The runtime page's call: JSON text in, a result document out, never an exception for bad input."""

from __future__ import annotations

import json

import pytest

from ph_composer_translation.composition import EXPORTERS, SECTIONS
from ph_composer_translation.entry import translate_json
from synthetic_sections import SectionA, SectionB, SectionC, document


def test_text_that_is_not_json_is_a_contract_failure() -> None:
    result = json.loads(translate_json("{"))
    assert result["state"] == "failed"
    assert result["failure"]["stage"] == "reading" and result["failure"]["code"] == "payload.contract"


def test_a_document_translates_with_the_given_sections() -> None:
    result = json.loads(translate_json(json.dumps(document()), (SectionA(), SectionB(), SectionC())))
    assert result["state"] == "complete" and result["summary"]["objects"] == 5


def test_the_product_build_lists_authored_report_face_zone_space_thermal_bridge_sections_and_no_exporter() -> None:
    assert [section.id for section in SECTIONS] == [
        "ph_composer.assemblies.export.constructions",
        "ph_composer.assemblies.export.material_sources",
        "ph_composer.zones.faces.export.faces",
        "ph_composer.windows.export.window_constructions",
        "ph_composer.windows.export.apertures",
        "ph_composer.zones.export.zones",
        "ph_composer.spaces.export.spaces",
        "ph_composer.thermal_bridges.export.thermal_bridges",
    ]
    assert EXPORTERS == ()
    empty = {"schema_version": 1, "run_id": "run-0", "sections": {}}
    result = json.loads(translate_json(json.dumps(empty)))
    assert result["state"] == "failed" and result["failure"]["code"] == "payload.contract"


def test_a_conformance_failure_raises_its_own_class_for_the_runtime_page(monkeypatch: pytest.MonkeyPatch) -> None:
    from ph_composer_translation import conformance, entry

    publishable = {"summary": {"publishable": True}, "canonical_model": {"hbjson": "{}"}}
    monkeypatch.setattr(entry, "translate_json", lambda text, sections: json.dumps(publishable))

    def refuse(*_args: object) -> None:
        raise ValueError("canonical identifiers repeat")

    monkeypatch.setattr(conformance, "check", refuse)
    with pytest.raises(conformance.ConformanceError):
        entry.export_json("{}")


def test_a_failure_is_reported_by_stage_class_and_package_frames_never_its_message(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from ph_composer_translation import conformance, entry

    publishable = {"summary": {"publishable": True}, "canonical_model": {"hbjson": "{}"}}
    monkeypatch.setattr(entry, "translate_json", lambda text, sections: json.dumps(publishable))
    secret = 'Zone North File "/tmp/ph_composer_translation/client_secret.py", line 2, in private_model'

    def refuse(*_args: object) -> None:
        raise ValueError(secret + "\nsecond line")

    monkeypatch.setattr(conformance, "check", refuse)
    report = json.loads(entry.export_report_json("{}"))

    failure = report["failure"]
    assert (failure["stage"], failure["error_class"]) == ("conformance", "ConformanceError")
    assert failure["frames"][0]["file"] == "ph_composer_translation/entry.py"
    assert all(frame["file"].startswith("ph_composer_translation/") for frame in failure["frames"])
    assert "Zone North" not in json.dumps(report) and "client_secret" not in json.dumps(report)
