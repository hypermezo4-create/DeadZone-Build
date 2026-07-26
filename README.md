# DeadZone-Build

DeadZone-Build is the public workflow surface for DeadZone System. Private engine repositories remain private and are referenced only through repository secrets.

## Control Bot builds

These workflows are reserved for `DeadZone-Control-Bot` and accept only an opaque `request_id`:

- `MEZO_Lite.yml`
- `gamingplus.yml`
- `frameworkpatcher.yml`

The workflow resolves ROM/JAR inputs and the Telegram builder identity through the signed DeadZone private contract, then publishes live stage telemetry back to DeadZone System.

## Direct GitHub builds

Manual builds are still available from the Actions tab without changing the Control Bot contract:

- `Lite_Test.yml` — direct DeadZone Lite build from an HTTPS ROM link.
- `GamingPlus_Direct.yml` — direct GamingPlus build from an HTTPS ROM link.
- `FrameworkPatcher_Direct.yml` — direct FrameworkPatcher build with Android/device/features/JAR inputs.

Direct workflows use the GitHub actor as the default builder label and do not require the Control Bot to be online.

## Member-facing identity

Telegram build messages use **DeadZone System** as the infrastructure identity. Provider, hosting, runner and private repository details are implementation-only and must not be added to member-facing live messages.

## Private repository configuration

The public workflows expect repository names/tokens through secrets such as:

- `LITE_ENGINE_REPOSITORY`
- `GAMINGPLUS_ENGINE_REPOSITORY`
- `FRAMEWORK_ENGINE_REPOSITORY`
- `FRAMEWORK_MODULE_REPOSITORY`
- `PRIVATE_REPO_TOKEN` (or the compatible private token already configured)
- `BUILD_PROGRESS_SECRET` for signed Control Bot contract/telemetry
- the existing Rclone delivery secrets

Never hardcode a private repository name into this public repository.
