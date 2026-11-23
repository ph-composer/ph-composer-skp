"""Select CI checks from the Git diff and validate simple documentation changes."""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit

# Help and the Agent Guide ship generated copies. The API reference and Contracts are test inputs.
FULL_CI_DOCS = {"docs/HELP.md", "docs/AGENT_GUIDE.md", "docs/API_REFERENCE.md", "context/CONTRACTS.md"}
PROSE = re.compile(r"(?:docs|context|planning)/.+\.md|README\.md|AGENTS\.md")
SKILL = re.compile(r"\.agents/skills/([a-z0-9-]+)/(?:SKILL\.md|agents/openai\.yaml)")
MIRROR = re.compile(r"\.claude/skills/([a-z0-9-]+)")
FENCE = re.compile(r" {0,3}(`{3,}|~{3,})")
INLINE_CODE = re.compile(r"(`+).*?\1(?!`)")
INLINE_LINK = re.compile(r"(?<!\\)\]\(\s*(?:<([^>\n]+)>|([^\s()<>]+))(?=\s|\))")


def git(*args: str) -> bytes:
    return subprocess.check_output(["git", *args], stderr=subprocess.PIPE)


def docs_changes(base: str) -> dict[Path, str] | None:
    """Return the added or edited docs and their Git status, or select full CI."""
    if not base or base.startswith("-"):
        return None
    try:
        # Raw NUL-delimited output preserves spaces and exposes executable and symlink modes.
        fields = git("diff", "--raw", "--no-renames", "-z", base, "HEAD", "--").split(b"\0")[:-1]
    except subprocess.CalledProcessError:
        return None

    changes: dict[Path, str] = {}
    for header, name in zip(fields[::2], fields[1::2], strict=True):
        old_mode, new_mode, _, _, status = header[1:].decode("ascii").split()
        path = os.fsdecode(name)
        if status not in {"A", "M"} or path in FULL_CI_DOCS or path.startswith("planning/native-acceptance/"):
            return None
        if PROSE.fullmatch(path) or SKILL.fullmatch(path):
            expected_mode = "100644"
        elif MIRROR.fullmatch(path):
            expected_mode = "120000"
        else:
            return None
        if new_mode != expected_mode or (status == "M" and old_mode != expected_mode):
            return None
        changes[Path(path)] = status
    return changes or None


def local_links(markdown: str) -> set[str]:
    """Find file paths in inline Markdown links outside code examples."""
    paths = set()
    fence = ""
    for line in markdown.splitlines():
        marker = FENCE.match(line)
        if fence:
            if marker and marker[1].startswith(fence) and not line[marker.end() :].strip():
                fence = ""
            continue
        if marker:
            fence = marker[1]
            continue
        if line.startswith(("    ", "\t")):
            continue
        for angle, plain in INLINE_LINK.findall(INLINE_CODE.sub("", line)):
            target = angle or plain
            # Raw brackets in a filename are valid paths, but not valid URL authorities.
            if target.startswith(("/", "#")) or re.match(r"[a-zA-Z][a-zA-Z0-9+.-]*:", target):
                continue
            path = unquote(urlsplit(target).path)
            if path:
                paths.add(path)
    return paths


def check_docs(base: str, changes: dict[Path, str]) -> list[str]:
    """Check new local file links and the entry point behind changed skill metadata or mirrors."""
    errors = []
    root = Path.cwd()
    for path, status in changes.items():
        if mirror := MIRROR.fullmatch(path.as_posix()):
            name = mirror[1]
            target = Path(".agents/skills") / name / "SKILL.md"
            if os.readlink(path) != f"../../.agents/skills/{name}" or not target.is_file() or target.is_symlink():
                errors.append(f"{path}: expected a link to the repository skill {name}")
        elif path.name == "openai.yaml":
            entry = path.parent.parent / "SKILL.md"
            if not entry.is_file() or entry.is_symlink():
                errors.append(f"{path}: missing skill entry point {entry}")
        else:
            newer = local_links(path.read_text(encoding="utf-8"))
            older = local_links(git("show", f"{base}:{path.as_posix()}").decode("utf-8")) if status == "M" else set()
            for link in sorted(newer - older):
                destination = (path.parent / link).resolve()
                if not destination.is_relative_to(root) or not destination.exists():
                    errors.append(f"{path}: missing local link target {link}")
    return errors


def main(base: str) -> int:
    changes = docs_changes(base)
    if changes is None:
        print("full")
        return 0
    errors = check_docs(base, changes)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("docs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1]))
