#!/bin/bash
# OPEN//77 Pterodactyl entrypoint: update, then start the server bound to the panel allocations.
cd /home/container || exit 1

log()  { printf '\033[1;36m[open77-egg]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[open77-egg]\033[0m %s\n' "$*"; }

bash ./open77-update.sh || warn "Update step failed, trying to start the installed build"
[[ -x ./Open77.Server ]] || { warn "No server installed. Reinstall the server from the panel."; exit 1; }

GAME_PORT="${SERVER_PORT:-11778}"
DL_PORT="${DOWNLOAD_PORT:-$((GAME_PORT + 1))}"
PUBLIC="${PUBLIC_IP:-}"
# Wings exposes the allocation IP; 0.0.0.0 or a private address cannot be advertised to players.
[[ -z "$PUBLIC" && -n "${SERVER_IP:-}" && "$SERVER_IP" != "0.0.0.0" ]] && PUBLIC="$SERVER_IP"

# First start without a config: Warden onboarding wizard (PIN printed in this console).
if [[ ! -f server.jsonc ]]; then
    if [[ -z "${WARDEN_PORT:-}" ]]; then
        warn "No server.jsonc and no WARDEN_PORT: add a TCP allocation for the setup wizard,"
        warn "or set SETUP_MODE=headless and reinstall to generate the config automatically."
        exit 1
    fi
    log "First start: open http://${PUBLIC:-<server-ip>}:${WARDEN_PORT}/ and enter the PIN below."
    log "In the wizard use game port ${GAME_PORT}/UDP and download port ${DL_PORT}/TCP."
    export OP77_WARDEN_SETUP_LISTEN="http://0.0.0.0:${WARDEN_PORT}"
    exec ./Open77.Server --config server.jsonc
fi

[[ -z "${DOWNLOAD_PORT:-}" ]] && warn "DOWNLOAD_PORT empty, using ${DL_PORT}: that port must be one of this server's allocations."
[[ -z "$PUBLIC" ]] && warn "No public IP (set PUBLIC_IP): players outside this host cannot reach the game or downloads."

# Customer-side settings first.
ARGS=(--no-setup --config server.jsonc --log-level "${LOG_LEVEL:-info}")
[[ -n "${SERVER_NAME:-}" ]]     && ARGS+=(--name "$SERVER_NAME")
[[ -n "${VISIBILITY:-}" ]]      && ARGS+=(--visibility "$VISIBILITY")
[[ -n "${OP77_DATABASE_CONNECTION:-}" ]] && ARGS+=(--set "database.enabled=true")
[[ "${WORKSHOP:-1}" == "1" ]]   && ARGS+=(--set "warden.hubFileGatewayOrigin=https://files.open2077.net")

# Free-form extra arguments from the panel, split on spaces, never glob-expanded.
if [[ -n "${EXTRA_ARGS:-}" ]]; then
    read -r -a EXTRA <<< "$EXTRA_ARGS"
    ARGS+=("${EXTRA[@]}")
fi

# Host-enforced settings last: on the command line the last value of a field wins, so
# EXTRA_ARGS, server.jsonc or Warden can never move the ports, address or slot count.
ARGS+=(--port "$GAME_PORT")
ARGS+=(--set "resources.download.enabled=true" --set "resources.download.listenUrl=http://0.0.0.0:${DL_PORT}/")
[[ -n "$PUBLIC" ]] && ARGS+=(--public-ip "$PUBLIC")
# Resource URL given to players: an HTTPS reverse proxy / CDN when set, else plain HTTP on the allocation.
if [[ -n "${DOWNLOAD_PUBLIC_URL:-}" ]]; then
    ARGS+=(--set "resources.download.publicBaseUrl=${DOWNLOAD_PUBLIC_URL%/}/")
elif [[ -n "$PUBLIC" ]]; then
    ARGS+=(--set "resources.download.publicBaseUrl=http://${PUBLIC}:${DL_PORT}/")
fi
[[ -n "${MAX_PLAYERS:-}" ]]     && ARGS+=(--max-players "$MAX_PLAYERS")
if [[ -n "${WARDEN_PORT:-}" ]]; then
    ARGS+=(--set "warden.enabled=true" --set "warden.listenUrl=http://0.0.0.0:${WARDEN_PORT}")
fi

log "Starting: ./Open77.Server ${ARGS[*]}"
exec ./Open77.Server "${ARGS[@]}"
