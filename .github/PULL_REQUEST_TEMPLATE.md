## What and why

<!-- What this changes in the egg and the problem it solves. Link the issue: Fixes #123 -->

## Kind of change

- [ ] Bug fix
- [ ] New variable or option
- [ ] Update / install logic (`open77-update.sh`)
- [ ] Startup logic (`open77-boot.sh`)
- [ ] Docs / CI only

## Checklist

- [ ] I edited the scripts or `build-egg.py`, never `egg-open77.json` by hand, then ran
      `python3 build-egg.py` and committed the regenerated egg.
- [ ] `tests/e2e.sh stable` passes locally (Docker only, no license needed).
- [ ] Host-enforced values (`PUBLIC_IP`, `DOWNLOAD_PORT`, `WARDEN_PORT`, `MAX_PLAYERS`) still come
      after `EXTRA_ARGS` and stay `user_editable: false`.
- [ ] Private state survives an update: `server.jsonc`, `acl.jsonc`, `tunables.json`, `.open77/`,
      resource `data/`.
- [ ] A new variable is documented in the README's Variables table, with who sets it.
- [ ] Nothing prints a secret (license key, database string) to the console.

## Upgrade notes for hosts

<!-- Does an existing server need a Reinstall to pick this up, a new allocation, or a variable
     change? Write "None" if it works after re-importing the egg. -->
