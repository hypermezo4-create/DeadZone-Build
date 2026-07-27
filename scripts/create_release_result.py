#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit


PROJECT_EDITIONS = {
    "lite": "Lite",
    "gamingplus": "GamingPlus",
    "ninja": "Ninja",
    "port": "Port",
    "legend": "Legend",
}
CODENAME_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{0,39}$")
VERSION_RE = re.compile(r"^[vV]?[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
FILE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,190}\.zip$")
DRIVE_HOSTS = {"drive.google.com", "docs.google.com"}


def _read_first(paths: list[Path]) -> str:
    for path in paths:
        if path.is_file():
            value = path.read_text(encoding="utf-8", errors="replace").strip()
            if value:
                return value
    return ""


def _normalize_edition_version(value: object) -> str:
    raw = str(value or "").strip()
    if not raw:
        raise SystemExit("release metadata is missing edition_version")
    normalized = raw if raw[:1] in {"V", "v"} else f"V{raw}"
    normalized = "V" + normalized[1:]
    if not VERSION_RE.fullmatch(normalized):
        raise SystemExit("release metadata has invalid edition_version")
    return normalized


def _safe_text(value: object, *, field: str, limit: int) -> str:
    text = str(value or "").strip()
    if not text or len(text) > limit or any(ord(ch) < 32 for ch in text):
        raise SystemExit(f"release metadata has invalid {field}")
    return text


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--engine", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--request-id", required=True)
    parser.add_argument("--project", required=True, choices=sorted(PROJECT_EDITIONS))
    args = parser.parse_args()

    engine = Path(args.engine).resolve()
    info = engine / "bin/runtime/info"
    internal_path = info / "release_internal.json"
    if not internal_path.is_file():
        raise SystemExit("private release metadata is missing")

    try:
        internal = json.loads(internal_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise SystemExit("private release metadata is invalid") from exc
    if not isinstance(internal, dict):
        raise SystemExit("private release metadata must be an object")

    expected_edition = PROJECT_EDITIONS[args.project]
    internal_project = str(internal.get("project") or "").strip().lower()
    internal_edition = str(internal.get("edition") or "").strip()
    if internal_project != args.project or internal_edition != expected_edition:
        raise SystemExit("private release identity does not match launcher project")

    codename = str(internal.get("codename") or "").strip().lower()
    if not CODENAME_RE.fullmatch(codename):
        raise SystemExit("release metadata has invalid codename")

    edition_version = _normalize_edition_version(
        internal.get("edition_version") or internal.get("deadzone_version")
    )
    rom_version = _safe_text(internal.get("rom_version"), field="rom_version", limit=160)
    android_version = _safe_text(internal.get("android_version"), field="android_version", limit=32)
    region = _safe_text(internal.get("region"), field="region", limit=64)

    file_name = str(internal.get("file_name") or "").strip()
    if not FILE_RE.fullmatch(file_name):
        raise SystemExit("release metadata has invalid file_name")

    output_path = _read_first([info / "output_path.txt"])
    artifact = Path(output_path) if output_path else engine / "out" / file_name
    if not artifact.is_file() or artifact.stat().st_size <= 0:
        raise SystemExit("release output archive is missing")
    if artifact.name != file_name:
        raise SystemExit("release output filename does not match metadata")

    declared_size = internal.get("size")
    if not isinstance(declared_size, int) or isinstance(declared_size, bool) or declared_size <= 0:
        raise SystemExit("release metadata has invalid size")
    actual_size = artifact.stat().st_size
    if declared_size != actual_size:
        raise SystemExit("release output size does not match private metadata")

    # SHA256 stays private. Its presence proves the private engine completed the
    # integrity calculation, but the checksum value must never enter the public
    # result artifact, website API, or Telegram message.
    sha256 = internal.get("sha256")
    if not isinstance(sha256, str) or not re.fullmatch(r"[0-9a-f]{64}", sha256):
        raise SystemExit("private integrity verification is missing")

    link = str(internal.get("drive_url") or "").strip() or _read_first(
        [info / "drive_link.txt", info / "upload_link.txt"]
    )
    parsed = urlsplit(link)
    host = (parsed.hostname or "").lower().rstrip(".")
    if parsed.scheme != "https" or host not in DRIVE_HOSTS or not parsed.path or parsed.path == "/":
        raise SystemExit("release delivery link is invalid")

    if str(internal.get("status") or "").strip().lower() != "uploaded":
        raise SystemExit("private release metadata is not in uploaded state")

    result = {
        "schema_version": "1.1",
        "request_id": args.request_id,
        "project": args.project,
        "edition": expected_edition,
        "edition_version": edition_version,
        "codename": codename,
        "status": "success",
        "provider": "google_drive",
        "url": link,
        "file_name": file_name,
        "size": actual_size,
        "rom_version": rom_version,
        "android_version": android_version,
        "region": region,
        "integrity_verified": True,
        "completed_at": datetime.now(timezone.utc).isoformat(),
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
