#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/NativeApp"

cd "$APP_DIR"

echo "[1/3] Building NativeApp..."
swift build >/tmp/inote_native_build.log 2>&1

BIN_DIR="$(swift build --show-bin-path)"
APP_BIN="$BIN_DIR/iNote2ObsidianApp"
if [[ ! -x "$APP_BIN" ]]; then
  echo "Smoke test failed: binary not found at $APP_BIN"
  exit 1
fi

echo "[2/3] Launching app process for liveness check..."
LOG_FILE="/tmp/inote_native_app_run.log"
"$APP_BIN" >"$LOG_FILE" 2>&1 &
APP_PID=$!

cleanup() {
  if kill -0 "$APP_PID" >/dev/null 2>&1; then
    kill "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

sleep 3
if ! kill -0 "$APP_PID" >/dev/null 2>&1; then
  echo "Smoke test failed: app exited too early."
  echo "---- app log ----"
  cat "$LOG_FILE" || true
  exit 1
fi

echo "[3/3] App stayed alive for 3s; stopping process..."
cleanup
trap - EXIT

echo "Smoke test passed."
