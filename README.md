# Open77 Pterodactyl Egg

`egg-open77.json` is the official egg for running [Open77](https://open2077.net) dedicated
servers (Cyberpunk 2077 multiplayer) on [Pterodactyl](https://pterodactyl.io). It is built for
hosting providers. On every start, a server checks the official CDN for the newest build, verifies
it and installs it before booting. You never bump versions by hand, and you don't need a new egg
when Open77 ships a release.

> [!IMPORTANT]
> **An Open77 server needs two allocations, three with Warden.** Pterodactyl only passes the
> primary allocation to the egg (`SERVER_PORT`). The extra ports have to be written into the
> server's variables, as below. A server with only its primary allocation starts, but players
> can't download its resources and can't join.

## Allocations

| Allocation | Protocol | Use | Variable | Required |
|---|---|---|---|---|
| primary, e.g. `11778` | UDP | game traffic | `SERVER_PORT` (set by Pterodactyl) | yes |
| additional, e.g. `11779` | TCP | resource downloads | `DOWNLOAD_PORT` | yes |
| additional, e.g. `11780` | TCP | Warden web panel and first-run wizard | `WARDEN_PORT` | recommended |

- Every allocation must be on the same IP, and the node firewall must let both UDP and TCP through.
- `DOWNLOAD_PORT` defaults to game port + 1. If you hand out consecutive ports, you can leave it
  empty, but the port must still be allocated to the server.
- `PUBLIC_IP` defaults to the allocation's IP. Set it when your allocations are on `0.0.0.0` or a
  private address behind NAT. Players are given this address.
- `PUBLIC_IP`, `DOWNLOAD_PORT`, `WARDEN_PORT` and `MAX_PLAYERS` are **admin-only**. Customers can
  see them but can't change them. These values are also applied after the customer's
  `EXTRA_ARGS`, `server.jsonc` and Warden settings, so nothing the customer does can move a port,
  the address or the slot count.
- **Billing automation**: have your provisioning module map the additional allocations to these
  variables, the same way query ports are mapped for other games. For example, the Pterodactyl
  WHMCS module's `port_array` setting takes `{"DOWNLOAD_PORT": 1, "WARDEN_PORT": 2}`.

## Install

1. Download [`egg-open77.json`](https://raw.githubusercontent.com/Open2077/open77-server-egg/main/egg-open77.json),
   then **Admin → Nests → Import Egg**.
2. Create the server with the **Debian + .NET 10** image (`ghcr.io/ptero-eggs/yolks:dotnet_10`).
   The legacy `pterodactyl/yolks:debian` image ships OpenSSL 1.1 and can't run the server.
3. Assign the allocations above and fill `DOWNLOAD_PORT`, `WARDEN_PORT` and, if needed, `PUBLIC_IP`.
4. Size it: the install takes about 170 MB and peaks around 420 MB during an update (archive
   plus staging), so give it **1 GB of disk**. An idle Freeroam server uses about 150 MB of RAM.
   Plan **1-2 GB** to cover players and extra resources.

The customer then needs an Open77 license key, minted at
[open2077.net/account/keys](https://open2077.net/account/keys) (it is shown only once). Without
it, the server doesn't appear on the master list.

| Setup mode | First start |
|---|---|
| `wizard` (default) | The console prints a PIN. The customer opens `http://PUBLIC_IP:WARDEN_PORT/`, enters the PIN, picks a template, pastes the license and creates the Warden admin. Once that's done, the game server starts in the same process. |
| `headless` | The install writes `server.jsonc` from the Freeroam template, and the server starts straight away with the license from `OP77_LICENSE_KEY`. Good for fully automated provisioning. |

A healthy start logs:

```text
[open77-egg] Up to date: 2.31.21+op77.138 (stable)
[open77-egg] Starting: ./Open77.Server --no-setup --config server.jsonc --log-level info ... --port 11778 ...
[INF] OPEN//77 server listening on UDP ...:11778 (players=32, tick=30, snapshots=20).
```

Pterodactyl marks the server online on that last line. **Stop** sends `^C`, the server's graceful
shutdown, which stops resources cleanly. Use **Kill** only as a last resort.

## How an update arrives

| Step | What happens |
|---|---|
| Version check | `cdn.open77.dev/server/latest.json` (or `unstable/latest.json`) gives the version, URL and archive SHA-256 |
| Download | only when the version differs from `package-manifest.json`, into `.open77-egg/tmp` on the volume (Wings' `/tmp` is a 100 MB tmpfs) |
| Verify | archive SHA-256, then every file against `package-manifest.json`, before anything is touched |
| Apply | shipped files are replaced and files the previous release shipped but this one dropped are deleted. Nothing else is touched |
| Self-repair | on every start, runtime files outside `resources/` are checked. A damaged install is downloaded again |
| CDN down | the installed build starts anyway |

Kept across updates and reinstalls: `server.jsonc`, `acl.jsonc`, `tunables.json`,
`.open77/` (master identity, resource signing key, Warden accounts), `server-icon.png`,
Workshop and custom resources, and every resource's `data/`.

## Variables

| Variable | Default | Set by | Effect |
|---|---|---|---|
| `PUBLIC_IP` | allocation IP | host | Address advertised to players |
| `DOWNLOAD_PORT` | game port + 1 | host | Resource download allocation (TCP) |
| `WARDEN_PORT` | | host | Warden panel allocation (TCP), empty disables Warden |
| `MAX_PLAYERS` | `32` | host | Slot count (`network.maximumPlayers`) |
| `OP77_LICENSE_KEY` | | customer | Platform license key, kept out of the command line |
| `OP77_CHANNEL` | `stable` | customer | `stable`, or `unstable` (test builds, needs the matching client) |
| `OP77_VERSION` | `latest` | customer | `latest`, or an exact version such as `2.31.21+op77.138` to pin or roll back |
| `AUTO_UPDATE` | `1` | customer | `0` leaves the installed build alone |
| `SETUP_MODE` | `wizard` | customer | `wizard` or `headless`, read at install |
| `OP77_TEMPLATE` | `freeroam` | customer | Template used by headless setup |
| `DOWNLOAD_PUBLIC_URL` | | customer | HTTPS URL of a reverse proxy in front of the download port |
| `SERVER_NAME`, `VISIBILITY` | | customer | Override `identity.name` / `identity.visibility`, empty keeps the file |
| `LOG_LEVEL` | `info` | customer | `trace`, `debug`, `info`, `warn`, `error` |
| `WORKSHOP` | `1` | customer | Lets Warden install Workshop creations |
| `OP77_DATABASE_CONNECTION` | | customer | MySQL/MariaDB connection string, enables the database bridge |
| `EXTRA_ARGS` | | customer | Appended as is, e.g. `--set simulation.tickRate=60`. Can't override host settings |

Variables are applied as startup overrides on every boot and never written to `server.jsonc`.
A value set here wins over the same field edited in Warden. Leave a customer variable empty to
manage that field from Warden.

## Structure

| Path | Responsibility |
|---|---|
| `egg-open77.json` | The egg to import. Generated, do not edit by hand. |
| `build-egg.py` | Builds the egg: variables, images, and the install script with the three scripts below embedded. |
| `open77-update.sh` | Version check, download, verification, update and self-repair. Runs at install and at every start. |
| `open77-boot.sh` | Startup command: update, then the server with the panel's ports and variables. |
| `open77-genconfig.sh` | `server.jsonc` from a template, for headless installs. |
| `tests/e2e.sh` | Install, boot, `^C`, upgrade, offline and wizard checks with the real Pterodactyl images. |
| `.github/workflows/ci.yml` | ShellCheck, egg freshness and the end-to-end checks, daily against the live CDN. |

After changing a script, run `python3 build-egg.py`, commit `egg-open77.json` and re-import the
egg. Servers pick up new scripts on **Reinstall**, which keeps the data listed above.

## Things worth knowing

- **Players must be on the same version.** A new stable build can raise the network protocol, and
  the launcher updates players at the same time. Pin `OP77_VERSION` if your community needs to
  stay on a build for a while.
- **Resource downloads are plain HTTP by default.** Packages are signed and hashed, so they can't be
  tampered with, but the traffic is not encrypted. Put a TLS proxy in front of `DOWNLOAD_PORT` and
  set `DOWNLOAD_PUBLIC_URL`.
- **Warden is plain HTTP, and the setup wizard is protected only by its PIN.** Finish setup
  right after the first start. For daily use, put TLS in front of Warden or leave `WARDEN_PORT`
  empty and reach it through a tunnel.
- **Don't edit the shipped resources in place.** Files from the archive are replaced on update.
  Copy a resource under a new name, or use Warden's Tuning tab.
- **Tested locally**: `tests/e2e.sh [stable|unstable]` needs only Docker and needs no license.
  It runs the server in its loopback developer mode.

## Documentation

- [Open77 docs](https://open2077.net/docs)
- [Host a server](https://open2077.net/docs/host-a-server)
- [Startup arguments](https://open2077.net/docs/server-startup)
- [Server licensing](https://open2077.net/docs/server-licensing)
- [Pterodactyl docs](https://docs.pterodactyl.io/v1/panel/getting-started)
- [Pterodactyl egg directory](https://eggs.pterodactyl.io/)

## License

MIT — see [`LICENSE`](LICENSE).
