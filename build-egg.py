#!/usr/bin/env python3
"""Builds egg-open77.json (PTDL_v2) with the helper scripts embedded in the install script."""
import json
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent


def embed(name):
    body = (HERE / name).read_text()
    return f"cat > {name} <<'OPEN77_EOF'\n{body}OPEN77_EOF\nchmod +x {name}\n"


install = (
    "#!/bin/bash\n"
    "# OPEN//77 dedicated server - Pterodactyl install / reinstall\n"
    "set -e\n"
    "apt-get update -qq && apt-get install -y -qq curl jq ca-certificates tar coreutils >/dev/null\n"
    "mkdir -p /mnt/server && cd /mnt/server\n\n"
    + embed("open77-update.sh") + "\n"
    + embed("open77-boot.sh") + "\n"
    + embed("open77-genconfig.sh") + "\n"
    "# Reinstall always pulls again; server.jsonc, acl.jsonc, .open77/ and resource data are kept.\n"
    "SERVER_DIR=/mnt/server OP77_FORCE=1 AUTO_UPDATE=1 bash ./open77-update.sh\n\n"
    'if [[ "${SETUP_MODE:-wizard}" == "headless" ]]; then\n'
    "    SERVER_DIR=/mnt/server bash ./open77-genconfig.sh\n"
    "fi\n"
    'echo "[open77-egg] Install complete"\n'
)


def var(name, env, default, rules, desc, viewable=True, editable=True):
    return {
        "name": name,
        "description": desc,
        "env_variable": env,
        "default_value": default,
        "user_viewable": viewable,
        "user_editable": editable,
        "rules": rules,
        "field_type": "text",
    }


egg = {
    "_comment": "DO NOT EDIT: FILE GENERATED AUTOMATICALLY BY PTERODACTYL PANEL - PTERODACTYL.IO",
    "meta": {
        "version": "PTDL_v2",
        "update_url": "https://raw.githubusercontent.com/Open2077/open77-server-egg/main/egg-open77.json",
    },
    "exported_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+00:00"),
    "name": "OPEN//77 (Cyberpunk 2077 multiplayer)",
    "author": "dop@dop42.xyz",
    "description": (
        "OPEN//77 dedicated server (Cyberpunk 2077 multiplayer). Pulls the latest build from the "
        "official CDN (cdn.open77.dev) on every start, checks its SHA-256, and keeps config, "
        "identities and resource data. Stable or unstable channel, or a pinned version."
    ),
    "features": None,
    "docker_images": {
        "Debian + .NET 10 (recommended)": "ghcr.io/ptero-eggs/yolks:dotnet_10",
        "Debian (ptero-eggs)": "ghcr.io/ptero-eggs/yolks:debian",
    },
    "file_denylist": [],
    "startup": "bash ./open77-boot.sh",
    "config": {
        "files": "{}",
        "startup": json.dumps({"done": "OPEN//77 server listening on UDP"}),
        "logs": "{}",
        "stop": "^C",
    },
    "scripts": {
        "installation": {
            "script": install,
            "container": "ghcr.io/ptero-eggs/installers:debian",
            "entrypoint": "bash",
        }
    },
    "variables": [
        var("License key", "OP77_LICENSE_KEY", "", "nullable|string|max:256",
            "Platform license key (op77_live_...) from https://open2077.net/account/keys. "
            "Required for the server to appear on the master list."),
        var("Update channel", "OP77_CHANNEL", "stable", "required|string|in:stable,unstable",
            "stable = production builds, unstable = test builds (newer client required)."),
        var("Version", "OP77_VERSION", "latest", "required|string|max:64",
            "latest = always the newest build of the channel. Otherwise an exact version to pin, "
            "e.g. 2.31.21+op77.138."),
        var("Auto update", "AUTO_UPDATE", "1", "required|boolean",
            "1 = check the CDN and update on every start. 0 = never touch the installed build."),
        var("Setup mode", "SETUP_MODE", "wizard", "required|string|in:wizard,headless",
            "wizard = first start opens Warden onboarding (PIN in the console, needs Warden port). "
            "headless = install writes server.jsonc from the template (reinstall to apply)."),
        var("Template (headless)", "OP77_TEMPLATE", "freeroam", "required|string|max:64",
            "Gamemode template under templates/ used by headless setup."),
        var("Public IP", "PUBLIC_IP", "", "nullable|ip",
            "Public IP players connect to. Empty = use the allocation IP (must not be 0.0.0.0). Set by the host.",
            editable=False),
        var("Resource download port", "DOWNLOAD_PORT", "", "nullable|integer|between:1,65535",
            "TCP port of a second allocation for resource downloads. Empty = game port + 1 (must also be allocated). "
            "Set by the host.", editable=False),
        var("Download public URL", "DOWNLOAD_PUBLIC_URL", "", "nullable|url|max:512",
            "Optional URL players download resources from, e.g. https://cdn.example.net/ behind a TLS "
            "reverse proxy pointing at the download port. Empty = http://PUBLIC_IP:DOWNLOAD_PORT/."),
        var("Warden port", "WARDEN_PORT", "", "nullable|integer|between:1,65535",
            "TCP port of an extra allocation for the Warden web panel / setup wizard. Empty = disabled. "
            "Set by the host.", editable=False),
        var("Max players", "MAX_PLAYERS", "32", "nullable|integer|between:1,4096",
            "Overrides network.maximumPlayers at every start. Empty = value from server.jsonc. "
            "Set by the host (slot count).", editable=False),
        var("Server name", "SERVER_NAME", "", "nullable|string|max:128",
            "Overrides identity.name at every start. Empty = value from server.jsonc / Warden."),
        var("Visibility", "VISIBILITY", "", "nullable|string|in:Public,Unlisted,Private",
            "Public, Unlisted or Private. Empty = value from server.jsonc."),
        var("Log level", "LOG_LEVEL", "info", "required|string|in:trace,debug,info,warn,error",
            "Minimum console severity."),
        var("Workshop installs", "WORKSHOP", "1", "required|boolean",
            "1 = allow installing Workshop creations from Warden (files.open2077.net)."),
        var("Database connection", "OP77_DATABASE_CONNECTION", "", "nullable|string|max:512",
            "Optional MySQL/MariaDB connection string for persistence. Kept out of the command line."),
        var("Extra arguments", "EXTRA_ARGS", "", "nullable|string|max:1024",
            "Appended to the command line, e.g. --set simulation.tickRate=60 --tick-rate 60."),
    ],
}

out = HERE / "egg-open77.json"
# Keep the previous export date when nothing else changed, so CI can diff the committed egg.
if out.exists():
    previous = json.loads(out.read_text())
    if {**previous, "exported_at": None} == {**egg, "exported_at": None}:
        egg["exported_at"] = previous["exported_at"]
out.write_text(json.dumps(egg, indent=4, ensure_ascii=False) + "\n")
print(f"wrote {out}")
