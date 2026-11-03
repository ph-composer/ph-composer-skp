"""Exercise evidence integrity and invalidation without running or mutating SketchUp."""

from __future__ import annotations

import fnmatch
import json
import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any
from unittest.mock import patch

import acceptance_ledger as ledger


class AcceptanceLedgerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        (self.root / "src").mkdir()
        (self.root / "src/action.rb").write_text("old")
        (self.root / "evidence.md").write_text("synthetic observations")
        subprocess.run(["git", "add", "."], cwd=self.root, check=True)
        self.case: dict[str, Any] = {"id": "C1", "paths": ["src/*"], "mode": "native", "native_control_required": True}
        self.cases = {"C1": self.case}
        self.result: dict[str, Any] = {
            "schema_version": 1,
            "case_id": "C1",
            "captured_at": "2026-09-30T12:00:00+00:00",
            "source_fingerprint": ledger.source_fingerprint(self.root, self.case["paths"]),
            "dependency_paths": self.case["paths"],
            "evidence_kind": "observed",
            "outcome": "pass",
            "assertions": [{"status": "pass", "observation": "Actual native toggle and state readback agree"}],
            "evidence": ["evidence.md"],
            "control": "combined",
            "host": {
                "sketchup": "26.1.188",
                "ruby": "3.2.2",
                "session_id": "synthetic-session",
                "fixture_id": "synthetic",
                "fixture_sha256": "a" * 64,
                "rbz_sha256": "b" * 64,
                "composition": "normal",
            },
        }
        path = self.root / ledger.RESULTS
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps(self.result) + "\n")

    def test_snapshot_cli_refuses_to_replace_an_existing_baseline(self) -> None:
        output = self.root / "baseline.json"
        output.write_text("original baseline")
        argv = ["acceptance_ledger", "--root", str(self.root), "snapshot", "C1", "--output", str(output)]
        with (
            patch("sys.argv", argv),
            patch.object(ledger, "read_catalog", return_value=self.cases),
            self.assertRaises(FileExistsError),
        ):
            ledger.main()
        self.assertEqual("original baseline", output.read_text())

    def test_changes_additions_and_deletions_invalidate_but_unrelated_file_does_not(self) -> None:
        baseline = self.result["source_fingerprint"]
        (self.root / "unrelated.md").write_text("new")
        self.assertEqual(baseline, ledger.source_fingerprint(self.root, self.case["paths"]))
        (self.root / "src/new.rb").write_text("new dependency")
        self.assertNotEqual(baseline, ledger.source_fingerprint(self.root, self.case["paths"]))
        (self.root / "src/new.rb").unlink()
        (self.root / "src/action.rb").unlink()
        self.assertNotEqual(baseline, ledger.source_fingerprint(self.root, self.case["paths"]))

    def commit_all(self) -> str:
        subprocess.run(["git", "add", "-A"], cwd=self.root, check=True)
        subprocess.run(
            ["git", "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "c"],
            cwd=self.root,
            check=True,
        )
        return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=self.root, text=True).strip()

    def test_a_changed_dependency_list_holds_while_its_files_are_unchanged_since_the_recorded_commit(self) -> None:
        (self.root / "docs").mkdir()
        (self.root / "docs/guide.md").write_text("guide")
        (self.root / "lib").mkdir()
        (self.root / "lib/helper.rb").write_text("helper")
        commit = self.commit_all()
        self.assertEqual(
            ledger.fingerprint_at(self.root, commit, ["src/*", "lib/*"]),
            ledger.source_fingerprint(self.root, ["src/*", "lib/*"]),
            "an unchanged tree fingerprints the same from git's objects as from the files",
        )
        recorded = {
            **self.result,
            "commit": commit,
            "dependency_paths": ["src/*", "docs/*"],
            "source_fingerprint": ledger.source_fingerprint(self.root, ["src/*", "docs/*"]),
        }
        (self.root / ledger.RESULTS).write_text(json.dumps(recorded) + "\n")
        narrowed = {**self.case, "paths": ["src/*"]}
        widened = {**self.case, "paths": ["src/*", "docs/*", "lib/*"]}
        (self.root / "docs/guide.md").write_text("reworded guide")
        self.assertEqual(
            "source_unchanged_environment_unchecked", ledger.status(self.root, {"C1": narrowed}, [])[0]["state"]
        )
        self.assertEqual("needs_recheck", ledger.status(self.root, {"C1": widened}, [])[0]["state"], "docs changed")
        (self.root / "docs/guide.md").write_text("guide")
        self.assertEqual(
            "source_unchanged_environment_unchecked", ledger.status(self.root, {"C1": widened}, [])[0]["state"]
        )
        (self.root / "src/action.rb").write_text("changed")
        self.assertEqual("needs_recheck", ledger.status(self.root, {"C1": narrowed}, [])[0]["state"])
        (self.root / "src/action.rb").write_text("old")
        dirty = {**recorded, "source_fingerprint": "0" * 64}
        (self.root / ledger.RESULTS).write_text(json.dumps(dirty) + "\n")
        self.assertEqual(
            "needs_recheck",
            ledger.status(self.root, {"C1": narrowed}, [])[0]["state"],
            "a result captured on uncommitted changes is not vouched for by its commit",
        )
        missing = {**recorded, "commit": "f" * 40}
        (self.root / ledger.RESULTS).write_text(json.dumps(missing) + "\n")
        self.assertEqual(
            "needs_recheck", ledger.status(self.root, {"C1": narrowed}, [])[0]["state"], "no commit, no proof"
        )

    def test_passing_source_is_not_an_automatic_current_host_pass(self) -> None:
        ledger.validate_result(self.root, self.cases, self.result)
        self.assertEqual("source_unchanged_environment_unchecked", ledger.status(self.root, self.cases, [])[0]["state"])
        (self.root / "src/action.rb").write_text("changed")
        self.assertEqual("needs_recheck", ledger.status(self.root, self.cases, [])[0]["state"])
        with self.assertRaisesRegex(ValueError, "baseline changed"):
            ledger.validate_result(self.root, self.cases, self.result)

    def test_native_control_and_assertion_failures_refuse_a_passing_result(self) -> None:
        self.result["control"] = "bridge"
        with self.assertRaisesRegex(ValueError, "native interaction"):
            ledger.validate_result(self.root, self.cases, self.result)
        self.result["control"] = "human"
        self.result["assertions"][0]["status"] = "unknown"
        with self.assertRaisesRegex(ValueError, "passing result"):
            ledger.validate_result(self.root, self.cases, self.result)

    def test_historical_evidence_is_retained_but_flagged_when_affected(self) -> None:
        self.result["evidence_kind"] = "historical_summary"
        (self.root / ledger.RESULTS).write_text(json.dumps(self.result) + "\n")
        self.assertEqual("historical_evidence", ledger.status(self.root, self.cases, [])[0]["state"])
        self.assertEqual("historical_affected", ledger.status(self.root, self.cases, ["src/action.rb"])[0]["state"])
        with self.assertRaisesRegex(ValueError, "historical"):
            ledger.validate_result(self.root, self.cases, self.result)

    def test_missing_evidence_and_deferred_scope_refuse(self) -> None:
        self.result["evidence"] = ["missing.md"]
        with self.assertRaisesRegex(ValueError, "existing"):
            ledger.validate_result(self.root, self.cases, self.result)
        self.case["deferred"] = True
        with self.assertRaisesRegex(ValueError, "scope decision"):
            ledger.validate_result(self.root, self.cases, self.result)

    def test_archived_evidence_resolves_without_rewriting_observed_or_historical_results(self) -> None:
        archived = self.root / "archive/evidence.md"
        archived.parent.mkdir()
        (self.root / "evidence.md").rename(archived)
        (self.root / ledger.EVIDENCE_LOCATIONS).write_text(json.dumps({"evidence.md": "archive/evidence.md"}))
        for kind in ("observed", "historical_summary"):
            with self.subTest(kind=kind):
                self.result["evidence_kind"] = kind
                original = json.dumps(self.result) + "\n"
                (self.root / ledger.RESULTS).write_text(original)
                self.assertEqual(["archive/evidence.md"], ledger.read_results(self.root, self.cases)[0]["evidence"])
                self.assertEqual(["archive/evidence.md"], ledger.status(self.root, self.cases, [])[0]["evidence"])
                self.assertEqual(original, (self.root / ledger.RESULTS).read_text())
        self.result["evidence_kind"] = "observed"
        with self.assertRaisesRegex(ValueError, "existing"):
            ledger.validate_result(self.root, self.cases, self.result)

    def test_unsafe_or_missing_archive_locations_refuse(self) -> None:
        invalid_locations: list[Any] = [
            [],
            {"../evidence.md": "evidence.md"},
            {"evidence.md": "/outside.md"},
            {"evidence.md": "../outside.md"},
            {"evidence.md": None},
            {"evidence.md": "missing.md"},
        ]
        for locations in invalid_locations:
            with self.subTest(locations=locations):
                (self.root / ledger.EVIDENCE_LOCATIONS).write_text(json.dumps(locations))
                with self.assertRaises(ValueError):
                    ledger.read_results(self.root, self.cases)


class CatalogPathsTest(unittest.TestCase):
    """The repository's catalog names the files each case exercises, so a stale screen is a signal."""

    ROOT = Path(__file__).resolve().parents[3]
    FOUNDATION_FOLDERS = frozenset(
        {
            "src/ph_composer/core/*",
            "src/ph_composer/session/*",
            "src/ph_composer/shell/*",
            "src/ph_composer/html/*",
            "tests/support/*",
        }
    )
    WHOLE_PRODUCT_CASES = frozenset({"A16", "E17"})

    def setUp(self) -> None:
        self.cases = ledger.read_catalog(self.ROOT)

    def test_only_whole_product_cases_depend_on_a_foundation_folder(self) -> None:
        broad = {
            case_id: sorted(self.FOUNDATION_FOLDERS.intersection(case["paths"]))
            for case_id, case in self.cases.items()
            if case_id not in self.WHOLE_PRODUCT_CASES and self.FOUNDATION_FOLDERS.intersection(case["paths"])
        }
        self.assertEqual({}, broad)

    def test_a_case_screens_what_it_reaches_without_naming_it(self) -> None:
        # E01's register checks the real panel loads with Zones / Faces and Export unchanged; a record engine
        # is handed its catalog; A12's runtime host loads the runtime page; LH1's hosted copy reaches a
        # feature's Library adapter, its Model switch the session, its setup dialog the request module and
        # its credential sweep both exports.
        reached = [
            ("E01", "src/ph_composer/html/features/zones/overview.js"),
            ("E01", "src/ph_composer/html/sections/export.js"),
            ("A10", "src/ph_composer/core/records/catalog.rb"),
            ("A13", "src/ph_composer/core/records/catalog.rb"),
            ("A12", "src/ph_composer/html/runtime/index.html"),
            ("A12", "src/ph_composer/html/runtime/runtime.js"),
            ("LH1", "src/ph_composer/features/assemblies/library_kind.rb"),
            ("LH1", "src/ph_composer/session/model_session.rb"),
            ("LH1", "src/ph_composer/html/request.js"),
            ("LH1", "src/ph_composer/export/task.rb"),
            ("LH1", "src/ph_composer/library/connection/credential_store.rb"),
        ]
        for case_id, name in reached:
            with self.subTest(case=case_id, name=name):
                self.assertTrue(any(fnmatch.fnmatchcase(name, pattern) for pattern in self.cases[case_id]["paths"]))

    def test_every_pattern_matches_a_source_file(self) -> None:
        names = ledger.source_names(self.ROOT)
        empty = [
            (case_id, pattern)
            for case_id, case in self.cases.items()
            for pattern in case["paths"]
            if not any(fnmatch.fnmatchcase(name, pattern) for name in names)
        ]
        self.assertEqual([], empty)


if __name__ == "__main__":
    unittest.main()
