# DeadZone Release Contract v1.1

All DeadZone ROM editions use the same post-upload result contract.

Canonical projects and editions:

- `lite` → `Lite`
- `gamingplus` → `GamingPlus`
- `ninja` → `Ninja`
- `port` → `Port`
- `legend` → `Legend`

Each edition owns its own version. There is no global DeadZone version.

Example:

```json
{
  "schema_version": "1.1",
  "request_id": "DZ-LT-20260727-0001",
  "project": "lite",
  "edition": "Lite",
  "edition_version": "V2.01",
  "codename": "zircon",
  "status": "success",
  "provider": "google_drive",
  "url": "https://drive.google.com/file/d/.../view",
  "file_name": "DeadZoneLite_v2.01_ZIRCON_OS3.0.5.0.WOOMIXM_GlobalStable-A16.zip",
  "size": 5000000000,
  "rom_version": "OS3.0.5.0.WOOMIXM",
  "android_version": "16",
  "region": "GlobalStable",
  "integrity_verified": true,
  "completed_at": "2026-07-27T08:00:00+00:00"
}
```

## Integrity privacy rule

The private engine must calculate and validate SHA256 before setting `integrity_verified=true`.
The checksum value itself must never be copied into the public result artifact, website API, website UI, or Telegram messages.

## Release identity

Website/Telegram release dedupe identity is:

`codename + edition + file_name`

Rebuilding the same identity updates the existing release. A different filename creates a new release. Two editions remain separate even when their version numbers or filenames happen to match.

## Transaction order

Build → private integrity verification → Google Drive upload → result contract → Control Bot catalog → website → Telegram publication.

Publication failure must never trigger a ROM rebuild or a second Drive upload.
