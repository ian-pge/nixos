#!/usr/bin/env python3
"""Emit a machine-readable package diff between two Nix closures."""

from __future__ import annotations

from functools import total_ordering
from itertools import zip_longest
import json
from pathlib import Path
import re
import subprocess
import sys


KINDS = ("upgraded", "downgraded", "changed", "added", "removed")
KIND_ORDER = {
    "added": 0,
    "removed": 1,
    "changed": 2,
    "upgraded": 3,
    "downgraded": 4,
}
STORE_NAME = re.compile(
    r"^[a-z0-9]{32}-(.+?)(-([0-9].*?))?(\.drv)?$"
)


@total_ordering
class VersionChunk:
    """One alphanumeric run using the ordering from Nix compareVersions."""

    def __init__(self, value: int | str):
        self.value = value

    def __eq__(self, other: object) -> bool:
        return isinstance(other, VersionChunk) and self.value == other.value

    def __lt__(self, other: object) -> bool:
        if not isinstance(other, VersionChunk):
            return NotImplemented
        left = self.value
        right = other.value
        left_is_int = isinstance(left, int)
        right_is_int = isinstance(right, int)
        if left_is_int and right_is_int:
            return left < right
        if (left == "" and right_is_int) or (left == "pre" and right != "pre"):
            return True
        if (left_is_int and right == "") or (right == "pre" and left != "pre"):
            return False
        if left_is_int:
            return False
        if right_is_int:
            return True
        return left < right


@total_ordering
class Version:
    """Nix-compatible comparable version retaining its original text."""

    def __init__(self, text: str | None):
        self.text = text or ""
        self.chunks: list[VersionChunk] = []
        remaining = self.text
        while remaining:
            first = remaining[0]
            if first.isdigit():
                end = 1
                while end < len(remaining) and remaining[end].isdigit():
                    end += 1
                self.chunks.append(VersionChunk(int(remaining[:end])))
            elif first.isalpha():
                end = 1
                while end < len(remaining) and remaining[end].isalpha():
                    end += 1
                self.chunks.append(VersionChunk(remaining[:end]))
            else:
                end = 1
                while (
                    end < len(remaining)
                    and not remaining[end].isdigit()
                    and not remaining[end].isalpha()
                ):
                    end += 1
            remaining = remaining[end:]

    def __eq__(self, other: object) -> bool:
        return isinstance(other, Version) and self.chunks == other.chunks

    def __lt__(self, other: object) -> bool:
        if not isinstance(other, Version):
            return NotImplemented
        empty = VersionChunk("")
        for left, right in zip_longest(
            self.chunks, other.chunks, fillvalue=empty
        ):
            if left != right:
                return left < right
        return False


class PackageSet:
    def __init__(self, store_names: list[str]):
        self.versions_by_name: dict[str, list[Version]] = {}
        for store_name in store_names:
            name, version = parse_store_name(store_name)
            self.versions_by_name.setdefault(name, []).append(Version(version))
        for versions in self.versions_by_name.values():
            versions.sort()

    def names(self):
        return self.versions_by_name.keys()

    def versions(self, name: str) -> list[Version]:
        return self.versions_by_name.get(name, [])

    def contains(self, name: str) -> bool:
        return name in self.versions_by_name


def parse_store_name(store_name: str) -> tuple[str, str]:
    match = STORE_NAME.fullmatch(Path(store_name).name)
    if match is None:
        raise ValueError(f"invalid Nix store path name: {store_name}")
    return match.group(1), match.group(3) or ""


def path_info(path: Path, *, recursive: bool) -> dict:
    command = ["nix", "path-info", "--json", "--json-format", "2"]
    if recursive:
        command.append("--recursive")
    command.append(str(path))
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        message = result.stderr.strip() or f"nix path-info exited with {result.returncode}"
        raise RuntimeError(message)
    try:
        document = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(f"nix path-info returned invalid JSON: {error}") from error
    return validate_path_info(document)


def validate_path_info(document: object) -> dict:
    if not isinstance(document, dict) or document.get("version") != 2:
        raise RuntimeError("nix path-info did not return JSON format 2")
    if document.get("storeDir") != "/nix/store":
        raise RuntimeError("nix path-info returned an unexpected store directory")
    info = document.get("info")
    if not isinstance(info, dict):
        raise RuntimeError("nix path-info JSON is missing its info object")
    return info


def selected_packages(root: Path, closure_info: dict, use_sw: bool) -> PackageSet:
    selection_root = root / "sw" if use_sw else root
    root_name = selection_root.resolve().name
    root_info = closure_info.get(root_name)
    if not isinstance(root_info, dict):
        root_info = path_info(selection_root, recursive=False).get(root_name)
    if not isinstance(root_info, dict):
        raise RuntimeError(f"nix path-info has no entry for {selection_root}")
    references = root_info.get("references")
    if not isinstance(references, list) or not all(
        isinstance(reference, str) for reference in references
    ):
        raise RuntimeError(f"nix path-info has invalid references for {selection_root}")
    return PackageSet(references)


def unique_version_texts(versions: list[Version]) -> list[str]:
    return list(dict.fromkeys(version.text for version in versions))


def classify(old_versions: list[Version], new_versions: list[Version]) -> str:
    if not old_versions:
        return "added"
    if not new_versions:
        return "removed"
    if old_versions[-1] < new_versions[0]:
        return "upgraded"
    if old_versions[0] > new_versions[-1]:
        return "downgraded"
    return "changed"


def build_diff(old_path: Path, new_path: Path) -> dict:
    old_resolved = old_path.resolve()
    new_resolved = new_path.resolve()
    old_info = path_info(old_resolved, recursive=True)
    new_info = path_info(new_resolved, recursive=True)
    old_packages = PackageSet(list(old_info))
    new_packages = PackageSet(list(new_info))
    use_sw = (old_resolved / "sw").is_dir() and (new_resolved / "sw").is_dir()
    old_selected = selected_packages(old_resolved, old_info, use_sw)
    new_selected = selected_packages(new_resolved, new_info, use_sw)
    changes = []

    for name in sorted(
        set(old_packages.names()) | set(new_packages.names()),
        key=str.casefold,
    ):
        old_versions = old_packages.versions(name)
        new_versions = new_packages.versions(name)
        selection_changed = old_selected.contains(name) != new_selected.contains(name)
        if old_versions == new_versions and not selection_changed:
            continue
        changes.append(
            {
                "name": name,
                "kind": classify(old_versions, new_versions),
                "oldVersions": unique_version_texts(old_versions),
                "newVersions": unique_version_texts(new_versions),
            }
        )

    changes.sort(key=lambda change: (
        KIND_ORDER[change["kind"]], change["name"].casefold()
    ))
    counts = {kind: 0 for kind in KINDS}
    for change in changes:
        counts[change["kind"]] += 1
    return {"changes": changes, "counts": counts, "total": len(changes)}


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: quickshell-update-diff OLD_SYSTEM NEW_SYSTEM", file=sys.stderr)
        return 2
    old_path, new_path = map(Path, sys.argv[1:])
    if not old_path.exists() or not new_path.exists():
        print("both system paths must exist", file=sys.stderr)
        return 2
    try:
        print(json.dumps(build_diff(old_path, new_path), separators=(",", ":")))
    except Exception as error:
        print(f"unable to compare Nix closures: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
