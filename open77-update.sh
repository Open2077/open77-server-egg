#!/bin/bash
# OPEN//77 updater for Pterodactyl: fetches the latest server build from the official CDN,
# verifies its SHA-256 and lays it over the install without touching private state.
#
# Env:
#   OP77_CHANNEL   stable (default) | unstable
#   OP77_VERSION   latest (default) or an exact version, e.g. 2.31.21+op77.138 (pin)
#   AUTO_UPDATE    1 (default) / 0 — when 0, only installs if nothing is installed yet
#   OP77_FORCE     1 to reinstall even if the version already matches
#   SERVER_DIR     install directory (default: current directory)
# Needs curl, tar, sha256sum, sed; jq is optional (the runtime yolk has none).
set -euo pipefail

CDN="https://cdn.open77.dev/server"
CHANNEL="${OP77_CHANNEL:-stable}"
WANTED="${OP77_VERSION:-latest}"
DIR="${SERVER_DIR:-$PWD}"
MANIFEST="$DIR/package-manifest.json"

log() { printf '\033[1;36m[open77-egg]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[open77-egg]\033[0m %s\n' "$*" >&2; exit 1; }

# The top-level "version" is the first one in both latest.json and package-manifest.json.
json_version() { sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$1" | head -n1; }

# A field of the linux-x64 build in latest.json.
build_field() { # $1 = latest.json, $2 = url|archiveSha256
    if command -v jq >/dev/null 2>&1; then
        jq -r --arg k "$2" '.builds["linux-x64"][$k] // empty' "$1"
    else
        sed -n '/"linux-x64"/,/}/p' "$1" | sed -n "s/.*\"$2\": *\"\([^\"]*\)\".*/\1/p" | head -n1
    fi
}

# Shipped file paths of a package-manifest.json, one per line (pretty-printed or minified).
manifest_paths() { grep -oE '"path": *"[^"]*"' "$1" | cut -d'"' -f4; }

# "sha256  path" lines of a package-manifest.json, for sha256sum -c.
manifest_checklist() {
    grep -oE '"(path|sha256)": *"[^"]*"' "$1" \
        | awk -F'"' '$2 == "path" { p = $4 } $2 == "sha256" && p != "" { print $4 "  " p; p = "" }'
}

CURRENT=""
[[ -f "$MANIFEST" ]] && CURRENT="$(json_version "$MANIFEST")"
INSTALLED=0
[[ -x "$DIR/Open77.Server" && -n "$CURRENT" ]] && INSTALLED=1

if [[ "${AUTO_UPDATE:-1}" != "1" && $INSTALLED == 1 ]]; then
    log "Auto-update disabled, keeping $CURRENT"
    exit 0
fi

# Never /tmp: Wings mounts it as a small tmpfs (100 MB by default), the archive and its
# extraction need about 300 MB. The server volume has the room.
WORK="$DIR/.open77-egg/tmp"
rm -rf "$WORK" && mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

if [[ "$WANTED" == "latest" || -z "$WANTED" ]]; then
    case "$CHANNEL" in
        stable)   MANIFEST_URL="$CDN/latest.json" ;;
        unstable) MANIFEST_URL="$CDN/unstable/latest.json" ;;
        *)        die "Unknown OP77_CHANNEL '$CHANNEL' (stable|unstable)" ;;
    esac
    if ! curl -fsSL --retry 3 --max-time 30 "$MANIFEST_URL" -o "$WORK/latest.json"; then
        [[ $INSTALLED == 1 ]] && { log "CDN unreachable, starting installed $CURRENT"; exit 0; }
        die "Cannot fetch $MANIFEST_URL"
    fi
    VERSION="$(json_version "$WORK/latest.json")"
    URL="$(build_field "$WORK/latest.json" url)"
    SHA="$(build_field "$WORK/latest.json" archiveSha256)"
    [[ -n "$SHA" ]] || die "Manifest has no archive hash for linux-x64, refusing an unverified download"
else
    VERSION="$WANTED"
    URL="$CDN/$VERSION/open77-server-$VERSION-linux-x64.tar.gz"
    SHA=""
fi
[[ -n "$VERSION" && -n "$URL" ]] || die "Manifest did not describe a linux-x64 build"

if [[ "$VERSION" == "$CURRENT" && $INSTALLED == 1 && "${OP77_FORCE:-0}" != "1" ]]; then
    # Runtime files outside resources/ are never edited by hand: a mismatch means a broken
    # install (interrupted copy, full disk), so it is reinstalled. Resources may be customised.
    if (cd "$DIR" && manifest_checklist package-manifest.json | grep -v '  resources/' \
            | sha256sum -c --quiet --strict >/dev/null 2>&1); then
        log "Up to date: $VERSION ($CHANNEL)"
        exit 0
    fi
    log "Installed runtime files are damaged, repairing $VERSION"
fi

log "Installing OPEN//77 server $VERSION (installed: ${CURRENT:-none})"
curl -fL --retry 3 --progress-bar "$URL" -o "$WORK/server.tar.gz" || die "Download failed: $URL"

if [[ -n "$SHA" ]]; then
    echo "$SHA  $WORK/server.tar.gz" | sha256sum -c --status || die "Archive SHA-256 mismatch, nothing applied"
    log "Archive SHA-256 verified"
else
    log "Pinned version: no CDN archive hash, relying on the per-file hashes of package-manifest.json"
fi

mkdir -p "$WORK/stage"
tar -xzf "$WORK/server.tar.gz" -C "$WORK/stage" --no-same-owner
rm -f "$WORK/server.tar.gz"
[[ -x "$WORK/stage/Open77.Server" && -f "$WORK/stage/package-manifest.json" ]] \
    || die "Archive layout unexpected (Open77.Server or package-manifest.json missing)"

# Check every staged file before anything in the install is touched.
(cd "$WORK/stage" && manifest_checklist package-manifest.json | sha256sum -c --quiet --strict) \
    || die "A file of the archive does not match package-manifest.json, nothing applied"

# The archive never ships these, but guard them anyway: they are the server's private state.
for f in server.jsonc acl.jsonc tunables.json server-icon.png .open77 .open77-egg; do
    rm -rf "${WORK:?}/stage/$f"
done

# Files the previous release shipped and this one no longer does. Only those are removed:
# Workshop resources, custom resources, resource data/ and logs were never in a manifest.
if [[ -f "$MANIFEST" ]]; then
    manifest_paths "$MANIFEST" | sort -u > "$WORK/old.txt"
    manifest_paths "$WORK/stage/package-manifest.json" | sort -u > "$WORK/new.txt"
    removed=0
    while IFS= read -r p; do
        [[ -z "$p" || "$p" == /* || "$p" == *..* ]] && continue
        rm -f -- "$DIR/$p" && removed=$((removed + 1))
    done < <(comm -23 "$WORK/old.txt" "$WORK/new.txt")
    (( removed > 0 )) && log "Removed $removed file(s) dropped by this release"
fi

cp -a "$WORK/stage/." "$DIR/"
chmod +x "$DIR/Open77.Server" "$DIR/start.sh" 2>/dev/null || true

(cd "$DIR" && manifest_checklist package-manifest.json | sha256sum -c --quiet --strict) \
    || die "Installed files do not match package-manifest.json (disk full?). Reinstall the server."

log "OPEN//77 server $VERSION ready"
