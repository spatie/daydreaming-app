#!/bin/bash
set -euo pipefail
# Xcode signs the outer application after this phase. Never sign with --deep.
if [[ "${CODE_SIGNING_ALLOWED:-YES}" != YES ]]; then exit 0; fi
identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then echo 'Sparkle signing requires EXPANDED_CODE_SIGN_IDENTITY.' >&2; exit 1; fi
framework="${TARGET_BUILD_DIR:?}/${FRAMEWORKS_FOLDER_PATH:?}/Sparkle.framework"
if [[ ! -d "$framework" ]]; then echo "Missing embedded Sparkle framework: $framework" >&2; exit 1; fi
sign_args=(--force --sign "$identity" --options runtime)
if [[ "$identity" != - ]]; then sign_args+=(--timestamp); fi
/usr/bin/codesign "${sign_args[@]}" "$framework/Versions/B/XPCServices/Installer.xpc"
/usr/bin/codesign "${sign_args[@]}" --preserve-metadata=entitlements "$framework/Versions/B/XPCServices/Downloader.xpc"
/usr/bin/codesign "${sign_args[@]}" "$framework/Versions/B/Autoupdate"
/usr/bin/codesign "${sign_args[@]}" "$framework/Versions/B/Updater.app"
/usr/bin/codesign "${sign_args[@]}" "$framework"
/usr/bin/codesign --verify --deep --strict "$framework"
