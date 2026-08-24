# Recovery Toolkit

After a fresh install of ubuntu on a portable usb, you can install the toolkit with
```
curl -fsSL https://raw.githubusercontent.com/kieferwaight/recovery-toolkit/main/bootstrap.sh | sudo bash
```

This loads the repo and runs `make install`, which installs packages and
idempotently symlinks the `bin/` commands into `/usr/local/bin`. Run `make all`
afterward if you also want the shellcheck pre-commit hook.

## Layout
- `bin/` - toolkit executables (secure erase, USB tuning, overlay boot setup)
- `setup-ssh` - enables SSH and authorizes GitHub public keys
- `setup-tailscale` - installs and authorizes Tailscale
- `lib/common.sh` - shared logging, `.env` loading, and safety guards
- `packages/` - apt package list installed by the toolkit
- `docs/` - usage notes per tool, plus LUKS layout planning
- `data/` (gitignored) - per-script audit logs, generated LUKS keys/headers

`data` is gitignored; each script under `bin/` appends timestamped entries to
`data/logs/<script>.log` via `lib/common.sh` for auditability of historical
actions applied to a machine (secure erases, key generation, etc).

The `.env` file is generated automatically from `.env.example` on first run
(`make env` or `lib/common.sh`'s `load_env`); most configuration can be left
at its defaults.

## Network Access Setup

Run these commands as root after installation. They are safe to rerun:

```bash
sudo setup-ssh
sudo setup-tailscale
```

`setup-ssh` installs and enables OpenSSH, then adds the current
`kieferwaight` GitHub public keys to the invoking user's `authorized_keys`
without duplicating existing entries. `setup-tailscale` installs and enables
Tailscale; when authorization is needed, it prints the browser URL to open.

See [docs/luks-layout-notes.md](docs/luks-layout-notes.md) for the plan around
LUKS key/header storage and disk identification.
