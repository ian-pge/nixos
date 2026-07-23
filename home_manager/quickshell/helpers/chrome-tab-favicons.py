#!/usr/bin/env python3
"""Attach local Chrome favicon-cache paths to a TabCtl JSON tab list."""

from __future__ import annotations

import hashlib
import json
import os
import sqlite3
import sys
from pathlib import Path


def favicon_database() -> Path:
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    return config_home / "google-chrome" / "Default" / "Favicons"


def cache_directory() -> Path:
    cache_home = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
    directory = cache_home / "quickshell" / "chrome-favicons"
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    return directory


def open_database(path: Path) -> sqlite3.Connection | None:
    if not path.is_file():
        return None
    try:
        # Chrome commonly holds the rollback journal open. Immutable read-only
        # mode gives us the last committed snapshot without contending with it.
        return sqlite3.connect(f"file:{path}?mode=ro&immutable=1", uri=True)
    except sqlite3.Error:
        return None


def icon_data(connection: sqlite3.Connection, page_url: str) -> bytes | None:
    try:
        row = connection.execute(
            """
            SELECT bitmap.image_data
              FROM icon_mapping AS mapping
              JOIN favicon_bitmaps AS bitmap
                ON bitmap.icon_id = mapping.icon_id
             WHERE mapping.page_url = ?
               AND bitmap.image_data IS NOT NULL
             ORDER BY bitmap.width DESC, bitmap.last_updated DESC
             LIMIT 1
            """,
            (page_url,),
        ).fetchone()
    except sqlite3.Error:
        return None
    return bytes(row[0]) if row and row[0] else None


def cached_icon(directory: Path, data: bytes) -> str:
    digest = hashlib.sha256(data).hexdigest()
    destination = directory / f"{digest}.png"
    if not destination.exists():
        temporary = destination.with_suffix(".tmp")
        temporary.write_bytes(data)
        temporary.chmod(0o600)
        temporary.replace(destination)
    return str(destination)


def main() -> int:
    try:
        tabs = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError):
        print(json.dumps({"ok": False, "tabs": [], "error": "Invalid TabCtl response"}))
        return 0

    if not isinstance(tabs, list):
        print(json.dumps({"ok": False, "tabs": [], "error": "Invalid TabCtl response"}))
        return 0

    connection = open_database(favicon_database())
    directory: Path | None = None
    try:
        if connection is not None:
            directory = cache_directory()
        for tab in tabs:
            if not isinstance(tab, dict):
                continue
            tab["iconPath"] = ""
            if connection is None or directory is None:
                continue
            data = icon_data(connection, str(tab.get("url", "")))
            if data:
                tab["iconPath"] = cached_icon(directory, data)
    finally:
        if connection is not None:
            connection.close()

    print(json.dumps({"ok": True, "tabs": tabs}, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
