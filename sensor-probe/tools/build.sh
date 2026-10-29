#!/usr/bin/env bash
# Build SensorProbe.prg for one device with the Connect IQ SDK on macOS/Linux.
#   tools/build.sh [device]        device defaults to venu2 (venu2s, venu2plus)
# Needs: Java 17 on PATH (or JAVA_HOME), the SDK + device files installed with
# Garmin's SDK Manager, and a developer key (created on first run, kept
# outside the repo in ~/.garmin/developer_key.der).
set -euo pipefail
DEVICE="${1:-venu2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CIQ="$HOME/Library/Application Support/Garmin/ConnectIQ"
[ -d "$CIQ" ] || CIQ="$HOME/.Garmin/ConnectIQ"

if [ -z "${SDK_BIN:-}" ]; then
  if [ -f "$CIQ/current-sdk.cfg" ]; then
    SDK_BIN="$(tr -d '\r\n' < "$CIQ/current-sdk.cfg")/bin"
  else
    SDK_BIN="$(ls -d "$CIQ"/Sdks/*/bin 2>/dev/null | sort | tail -1)"
  fi
fi
[ -x "$SDK_BIN/monkeyc" ] || { echo "monkeyc not found (SDK_BIN=$SDK_BIN). Install the SDK with the SDK Manager." >&2; exit 1; }

if ! command -v java >/dev/null 2>&1; then
  for j in /opt/homebrew/opt/openjdk@17/bin /usr/local/opt/openjdk@17/bin; do
    [ -x "$j/java" ] && export PATH="$j:$PATH" && break
  done
fi

KEY="${CIQ_KEY:-$HOME/.garmin/developer_key.der}"
if [ ! -f "$KEY" ]; then
  mkdir -p "$(dirname "$KEY")"
  openssl genrsa -out "${KEY%.der}.pem" 4096
  openssl pkcs8 -topk8 -inform PEM -outform DER -in "${KEY%.der}.pem" -out "$KEY" -nocrypt
  echo "Created developer key $KEY (keep it; sideloaded updates must use the same key)."
fi

mkdir -p "$ROOT/bin"
"$SDK_BIN/monkeyc" -d "$DEVICE" -f "$ROOT/monkey.jungle" -o "$ROOT/bin/SensorProbe.prg" -y "$KEY" -w
echo "Built $ROOT/bin/SensorProbe.prg for $DEVICE"
