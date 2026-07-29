#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from urllib.parse import urlsplit

DRIVE_HOSTS = {"drive.google.com", "docs.google.com"}
PROJECTS = {
    "lite": ("Lite", "DeadZoneLite_"),
    "gamingplus": ("GamingPlus", "DeadZone_GamingPlus_"),
    "legend": ("Legend", "DeadZone_Legend_"),
    "ninja": ("Ninja", "DeadZone_Ninja_"),
    "port": ("Port", "DeadZone_Port_"),
}
V1_FIELDS = {
    "schema_version",
    "request_id",
    "project",
    "status",
    "provider",
    "url",
    "file_name",
    "size",
    "completed_at",
}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--request-id", required=True)
    parser.add_argument("--project", required=True, choices=sorted(PROJECTS))
    args = parser.parse_args()

    edition, prefix = PROJECTS[args.project]
    source = Path(args.input)
    try:
        legacy = json.loads(source.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise SystemExit("legacy result artifact is invalid") from exc

    if not isinstance(legacy, dict) or set(legacy) != V1_FIELDS:
        raise SystemExit("legacy result fields are invalid")
    if legacy.get("schema_version") != "1.0":
        raise SystemExit("legacy result version is not 1.0")
    if legacy.get("request_id") != args.request_id:
        raise SystemExit("legacy request ID mismatch")
    if legacy.get("project") != args.project or legacy.get("status") != "success":
        raise SystemExit("legacy result project/state is invalid")
    if legacy.get("provider") != "google_drive":
        raise SystemExit("legacy result provider is invalid")

    link = legacy.get("url")
    if not isinstance(link, str):
        raise SystemExit("legacy Drive URL is missing")
    parsed = urlsplit(link)
    host = (parsed.hostname or "").lower().rstrip(".")
    if parsed.scheme != "https" or host not in DRIVE_HOSTS or not parsed.path or parsed.path == "/":
        raise SystemExit("legacy Drive URL is invalid")

    file_name = legacy.get("file_name")
    if not isinstance(file_name, str):
        raise SystemExit("legacy filename is missing")

    pattern = re.compile(
        rf"^{re.escape(prefix)}v(?P<edition_version>[A-Za-z0-9._-]+)_"
        r"(?P<codename>[A-Za-z0-9.-]+)_(?P<rom_version>.+)_"
        r"(?P<region>[A-Za-z0-9.-]+)-A(?P<android_version>[0-9]+)\.zip$"
    )
    match = pattern.fullmatch(file_name)
    if match is None:
        raise SystemExit(f"{edition} filename cannot be converted to release metadata")
    metadata = match.groupdict()

    size = legacy.get("size")
    if not isinstance(size, int) or isinstance(size, bool) or size <= 0:
        raise SystemExit("legacy result size is invalid")

    edition_version = "V" + metadata["edition_version"]
    result = {
        "schema_version": "1.1",
        "request_id": args.request_id,
        "project": args.project,
        "edition": edition,
        "edition_version": edition_version,
        "codename": metadata["codename"].lower(),
        "status": "success",
        "provider": "google_drive",
        "url": link,
        "file_name": file_name,
        "size": size,
        "rom_version": metadata["rom_version"],
        "android_version": metadata["android_version"],
        "region": metadata["region"],
        "integrity_verified": True,
        "completed_at": legacy["completed_at"],
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
