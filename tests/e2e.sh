#!/bin/bash
# End-to-end test of the egg with the real Pterodactyl images, the way Wings runs them:
# install container, then the runtime yolk as uid 988 with a 100 MB /tmp and STARTUP eval'd
# by the yolk entrypoint. Needs docker, jq, curl. No license needed: the run uses the loopback
# developer mode, which the server only accepts with the master disabled and visibility Private.
#
#   tests/e2e.sh [stable|unstable]
set -euo pipefail

CHANNEL="${1:-stable}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
SRV="$WORK/srv"
NAME="op77-e2e-$$"
INSTALLER="ghcr.io/ptero-eggs/installers:debian"
YOLK="$(jq -r '.docker_images | to_entries[0].value' "$ROOT/egg-open77.json")"
mkdir -p "$SRV"

cleanup() {
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    docker run --rm -v "$WORK:/w" "$INSTALLER" rm -rf /w/srv >/dev/null 2>&1 || true
    rm -rf "$WORK"
}
trap cleanup EXIT

pass() { printf '\033[1;32mPASS\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL\033[0m %s\n' "$*"; exit 1; }
# No grep -q behind a pipe: it exits on the first match, the writer dies of SIGPIPE and
# pipefail turns the match into a failure. Let grep read everything instead.
logs_have() { docker logs "$NAME" 2>&1 | grep -F -- "$1" >/dev/null; }

jq -r '.scripts.installation.script' "$ROOT/egg-open77.json" > "$WORK/install.sh"

install() { # extra docker -e flags
    docker run --rm --tmpfs /tmp:size=100m -v "$SRV:/mnt/server" -v "$WORK/install.sh:/install.sh:ro" \
        "$@" "$INSTALLER" bash /install.sh
    docker run --rm -v "$SRV:/s" "$INSTALLER" chown -R 988:988 /s   # Wings does this after install
}

runtime() { # extra docker flags, then the command
    docker run --user 988:988 --tmpfs /tmp:size=100m -v "$SRV:/home/container" \
        -e SERVER_PORT=27015 -e SERVER_IP=0.0.0.0 -e PUBLIC_IP=203.0.113.10 -e DOWNLOAD_PORT=27016 \
        -e OP77_CHANNEL="$CHANNEL" -e OP77_VERSION=latest -e AUTO_UPDATE=1 "$@"
}

echo "== install (headless, $CHANNEL) with $INSTALLER"
install -e SETUP_MODE=headless -e OP77_CHANNEL="$CHANNEL" -e MAX_PLAYERS=40 | tee "$WORK/install.log"
grep -q 'Archive SHA-256 verified' "$WORK/install.log" || fail "archive not verified"
[[ -f "$SRV/server.jsonc" ]] || fail "server.jsonc not generated"
pass "install"

echo "== configuration accepted by the server in $YOLK"
runtime --rm -e EXTRA_ARGS="--set masterServer.enabled=false --check-config" -e STARTUP='bash ./open77-boot.sh' \
    "$YOLK" | tee "$WORK/check.log"
grep -q 'Configuration valid' "$WORK/check.log" || fail "--check-config rejected the configuration"
grep -q 'advertised=203.0.113.10:27015' "$WORK/check.log" || fail "public endpoint not applied"
grep -q 'public=http://203.0.113.10:27016' "$WORK/check.log" || fail "download URL not applied"
pass "config"

echo "== host-locked port and slots win over the customer's EXTRA_ARGS"
runtime --rm -e MAX_PLAYERS=24 -e STARTUP='bash ./open77-boot.sh' \
    -e EXTRA_ARGS="--max-players 999 --set network.port=1234 --set masterServer.enabled=false --check-config" \
    "$YOLK" | tee "$WORK/lock.log"
grep -q 'UDP port=27015, advertised=203.0.113.10:27015, maxPlayers=24' "$WORK/lock.log" \
    || fail "EXTRA_ARGS overrode a host-enforced setting"
pass "host lock"

echo "== start, ready line, graceful ^C"
runtime -d --name "$NAME" -e VISIBILITY=Private -e STARTUP='bash ./open77-boot.sh' \
    -e EXTRA_ARGS="--set masterServer.enabled=false --set masterServer.devLocalAuth=true" "$YOLK" >/dev/null
DONE="$(jq -r '.config.startup | fromjson | .done' "$ROOT/egg-open77.json")"
for _ in $(seq 1 90); do logs_have "$DONE" && break; sleep 1; done
logs_have "$DONE" || { docker logs "$NAME" 2>&1 | tail -40; fail "done line '$DONE' never printed"; }
pass "ready"
sleep 5   # let the resources finish starting, as on a live server
docker kill -s INT "$NAME" >/dev/null
[[ "$(timeout 30 docker wait "$NAME")" == "0" ]] || { docker logs "$NAME" 2>&1 | tail -30; fail "SIGINT did not stop the server cleanly"; }
logs_have 'Server stopped' || { docker logs "$NAME" 2>&1 | tail -30; fail "no graceful shutdown"; }
docker rm "$NAME" >/dev/null
pass "stop"

echo "== private state survives a reinstall, dropped files go, damaged runtime is repaired"
docker run --rm -v "$SRV:/s" "$INSTALLER" bash -c '
    mkdir -p /s/resources/my_res/data && echo keep > /s/resources/my_res/data/x.json
    echo "// mine" >> /s/server.jsonc
    echo stale > /s/resources/system/open77_admin/STALE.lua
    sed -i "0,/\"path\": \"LICENSE\"/s##\"path\": \"resources/system/open77_admin/STALE.lua\", \"sha256\": \"0\"}, {\"path\": \"LICENSE\"#" /s/package-manifest.json
    chown -R 988:988 /s'
install -e SETUP_MODE=headless -e OP77_CHANNEL="$CHANNEL" > /dev/null
[[ "$(cat "$SRV/resources/my_res/data/x.json")" == keep ]] || fail "resource data lost"
[[ "$(tail -n1 "$SRV/server.jsonc")" == "// mine" ]] || fail "server.jsonc overwritten"
[[ ! -e "$SRV/resources/system/open77_admin/STALE.lua" ]] || fail "dropped file kept"
docker run --rm -v "$SRV:/s" "$INSTALLER" bash -c 'echo x >> /s/Open77.Server.deps.json'
runtime --rm --entrypoint bash "$YOLK" -c 'cd /home/container && bash ./open77-update.sh' | tee "$WORK/repair.log"
grep -q 'repairing' "$WORK/repair.log" || fail "damaged runtime file not detected"
runtime --rm --entrypoint bash "$YOLK" -c 'cd /home/container && bash ./open77-update.sh' | grep 'Up to date' >/dev/null \
    || fail "repair did not restore the files"
pass "upgrade safety"

echo "== CDN unreachable: installed build still starts"
runtime --rm --network none --entrypoint bash "$YOLK" -c 'cd /home/container && bash ./open77-update.sh' \
    | grep 'CDN unreachable' >/dev/null || fail "no offline fallback"
pass "offline"

echo "== wizard mode on a fresh install"
docker run --rm -v "$WORK:/w" "$INSTALLER" rm -rf /w/srv && mkdir -p "$SRV"
install -e SETUP_MODE=wizard -e OP77_CHANNEL="$CHANNEL" > /dev/null
[[ ! -f "$SRV/server.jsonc" ]] || fail "wizard install must not write server.jsonc"
runtime -d --name "$NAME" -p 127.0.0.1:27017:27017 -e WARDEN_PORT=27017 -e STARTUP='bash ./open77-boot.sh' "$YOLK" >/dev/null
for _ in $(seq 1 60); do curl -sf -o /dev/null http://127.0.0.1:27017/ && break; sleep 1; done
curl -sf -o /dev/null http://127.0.0.1:27017/ || { docker logs "$NAME" 2>&1 | tail -30; fail "setup wizard not reachable"; }
logs_have 'Setup PIN' || fail "no setup PIN in the console"
pass "wizard"

printf '\n\033[1;32mAll egg checks passed (%s)\033[0m\n' "$CHANNEL"
