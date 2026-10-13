#!/bin/bash
# Writes a minimal server.jsonc for headless installs (SETUP_MODE=headless).
# Ports, public IP and player count are overridden at every boot by open77-boot.sh.
set -euo pipefail
DIR="${SERVER_DIR:-$PWD}"
cd "$DIR"
[[ -f server.jsonc ]] && { echo "[open77-egg] server.jsonc exists, leaving it untouched"; exit 0; }

TEMPLATE="${OP77_TEMPLATE:-freeroam}"
[[ -f "templates/$TEMPLATE/template.json" ]] || { echo "[open77-egg] Unknown template '$TEMPLATE'" >&2; exit 1; }

# Template lists resource names; package-manifest.json maps them to directories under resources/.
LOAD="$(jq -c --slurpfile m package-manifest.json '[.resources[] | $m[0].resources[.] // .]' "templates/$TEMPLATE/template.json")"
TAGS="$(jq -c '.defaultTags // []' "templates/$TEMPLATE/template.json")"

jq -n \
  --arg name "${SERVER_NAME:-OPEN//77 server}" \
  --arg desc "${SERVER_DESCRIPTION:-Hosted with Pterodactyl}" \
  --arg vis "${VISIBILITY:-Public}" \
  --argjson port "${SERVER_PORT:-11778}" \
  --argjson max "${MAX_PLAYERS:-32}" \
  --argjson load "$LOAD" \
  --argjson tags "$TAGS" \
'{
  "$schema": "./config/server.schema.json",
  schemaVersion: 1,
  identity: { name: $name, description: $desc, locale: "en", tags: $tags, visibility: $vis },
  network: { port: $port, publicEndpoint: null, maximumPlayers: $max },
  simulation: { tickRate: 30, snapshotRate: 20, expectedGameBuild: 23100, helloTimeoutSeconds: 10 },
  resources: { enabled: true, root: "resources", load: $load, autoStart: true },
  masterServer: { enabled: true, url: "https://master.open2077.net/", licenseKeyEnvironmentVariable: "OP77_LICENSE_KEY" }
}' > server.jsonc

echo "[open77-egg] server.jsonc generated from template '$TEMPLATE'"
