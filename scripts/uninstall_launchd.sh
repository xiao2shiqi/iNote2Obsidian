#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <plist_path>"
  exit 1
fi

PLIST_PATH="$1"

if [[ -f "$PLIST_PATH" ]]; then
  launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
  rm -f "$PLIST_PATH"
  echo "Unloaded and removed: $PLIST_PATH"
else
  echo "No plist found: $PLIST_PATH"
fi
