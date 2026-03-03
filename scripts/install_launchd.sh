#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "Usage: $0 <python_bin> <config_path> <stdout_log> <stderr_log> <plist_output_path>"
  exit 1
fi

PYTHON_BIN="$1"
CONFIG_PATH="$2"
STDOUT_LOG="$3"
STDERR_LOG="$4"
PLIST_PATH="$5"

TEMPLATE_DIR="$(cd "$(dirname "$0")/.." && pwd)/launchd"
TEMPLATE="$TEMPLATE_DIR/com.inote2obsidian.sync.plist.template"

mkdir -p "$(dirname "$PLIST_PATH")"

sed -e "s#__PYTHON_BIN__#$PYTHON_BIN#g" \
    -e "s#__CONFIG_PATH__#$CONFIG_PATH#g" \
    -e "s#__STDOUT_LOG__#$STDOUT_LOG#g" \
    -e "s#__STDERR_LOG__#$STDERR_LOG#g" \
    "$TEMPLATE" > "$PLIST_PATH"

launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl load "$PLIST_PATH"

echo "Loaded launch agent: $PLIST_PATH"
