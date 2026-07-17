#!/usr/bin/env bash
#
# One-command setup for reviewers: generates the mock API's seed data and
# starts JSON Server on localhost:3000.
#
# Usage:
#   ./scripts/setup.sh            # generate data (if missing) + start server
#   ./scripts/setup.sh --reseed   # force-regenerate images/db.json, then start
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

PORT=3000
STATIC_DIR="mock-server/public"
IMAGES_DIR="$STATIC_DIR/images"
DB_FILE="mock-server/db.json"

echo "== Rogers Marketplace — mock server setup =="

if ! command -v node >/dev/null 2>&1; then
    echo "error: Node.js is required (https://nodejs.org) and was not found on PATH." >&2
    exit 1
fi
if ! command -v swift >/dev/null 2>&1; then
    echo "error: the Swift toolchain (ships with Xcode) is required and was not found on PATH." >&2
    exit 1
fi

NODE_VERSION="$(node --version)"
echo "Using Node ${NODE_VERSION}"

FORCE_RESEED=false
if [[ "${1:-}" == "--reseed" ]]; then
    FORCE_RESEED=true
fi

if [[ "$FORCE_RESEED" == true || ! -d "$IMAGES_DIR" || -z "$(ls -A "$IMAGES_DIR" 2>/dev/null)" ]]; then
    echo "-- Generating placeholder images..."
    swift scripts/generate-placeholder-images.swift
else
    echo "-- Placeholder images already present, skipping (use --reseed to regenerate)."
fi

if [[ "$FORCE_RESEED" == true || ! -f "$DB_FILE" ]]; then
    echo "-- Seeding 200 mock listings..."
    node mock-server/seed.mjs
else
    echo "-- $DB_FILE already exists, skipping (use --reseed to regenerate)."
fi

LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "<your-Mac-IP>")"

cat <<EOF

== Ready ==
JSON Server will run at http://localhost:${PORT}

  • iOS Simulator:      use the default server URL, http://localhost:${PORT}
  • Physical device:    open the app's Settings tab and set the server URL to
                         http://${LAN_IP}:${PORT}
                         (device and Mac must be on the same Wi-Fi network)

Try it once the server is running:
  curl http://localhost:${PORT}/listings | head -c 300

Press Ctrl+C to stop the server.
EOF

exec npx --yes json-server@0.17.4 \
    --host 0.0.0.0 \
    --port "$PORT" \
    --static "$STATIC_DIR" \
    "$DB_FILE"
