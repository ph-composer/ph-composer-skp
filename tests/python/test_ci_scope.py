"""Check the CI routes against real Git trees, including the docs checks."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[2] / "tools" / "ci_scope.py"


def git(repo: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()


def write(repo: Path, name: str, text: str) -> None:
    path = repo / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def commit(repo: Path) -> None:
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", "Synthetic CI scope test")


@pytest.fixture
def repo(tmp_path: Path) -> Path:
    git(tmp_path, "init", "-q")
    git(tmp_path, "config", "user.name", "CI scope test")
    git(tmp_path, "config", "user.email", "ci-scope@example.test")
    write(tmp_path, "docs/Guide with spaces.md", "# Guide\n")
    write(tmp_path, "docs/Notes.md", "[Older link](missing.md)\n")
    commit(tmp_path)
    return tmp_path


def scope(repo: Path, base: str = "HEAD^1") -> subprocess.CompletedProcess[str]:
    return subprocess.run([sys.executable, str(SCRIPT), base], cwd=repo, capture_output=True, text=True, check=False)


def test_prose_and_repo_skill_files_take_the_fast_path(repo: Path) -> None:
    write(
        repo,
        "docs/Notes.md",
        "[Older link](missing.md)\n[Guide](<Guide with spaces.md#guide>)\n"
        "[External](https://example.test)\n`[example](missing-inline.md)`\n"
        "```md\n[example](missing-code.md)\n```\n\n    [example](missing-indented.md)\n",
    )
    write(repo, ".agents/skills/example/SKILL.md", "# Example\n")
    write(repo, ".agents/skills/example/agents/openai.yaml", "interface: {}\n")
    mirror = repo / ".claude/skills/example"
    mirror.parent.mkdir(parents=True)
    mirror.symlink_to("../../.agents/skills/example")
    commit(repo)

    result = scope(repo)

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "docs"


@pytest.mark.parametrize(
    "path",
    [
        "src/ph_composer.rb",
        ".github/workflows/ci.yml",
        ".agents/skills/example/scripts/helper.py",
        "docs/HELP.md",
        "docs/AGENT_GUIDE.md",
        "docs/API_REFERENCE.md",
        "context/CONTRACTS.md",
        Path("planning", "native-acceptance", "evidence", "example.md").as_posix(),
    ],
)
def test_any_substantive_path_runs_the_full_matrix(repo: Path, path: str) -> None:
    write(repo, "docs/Notes.md", "Updated notes.\n")
    write(repo, path, "changed\n")
    commit(repo)

    result = scope(repo)

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "full"


def test_renames_and_unknown_comparisons_run_the_full_matrix(repo: Path) -> None:
    git(repo, "mv", "docs/Notes.md", "docs/Renamed.md")
    commit(repo)

    for base in ("HEAD^1", "HEAD", "0" * 40):
        result = scope(repo, base)
        assert result.returncode == 0, result.stderr
        assert result.stdout.strip() == "full"


def test_broken_new_references_fail_docs_checks(repo: Path) -> None:
    write(repo, "docs/Notes.md", "[Older link](missing.md)\n[New link](missing-new.md)\n")
    write(repo, ".agents/skills/missing-entry/agents/openai.yaml", "interface: {}\n")
    mirror = repo / ".claude/skills/example"
    mirror.parent.mkdir(parents=True)
    mirror.symlink_to("../../.agents/skills/missing-entry")
    commit(repo)

    result = scope(repo)

    assert result.returncode == 1
    assert "missing-new.md" in result.stderr
    assert "missing.md" not in result.stderr
    assert "missing skill entry point" in result.stderr
    assert "expected a link to the repository skill" in result.stderr
