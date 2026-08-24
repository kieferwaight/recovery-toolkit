# Recovery Toolkit

After a fresh install of ubuntu on a portable usb, you can install the toolkit with
```
curl -fsSL https://raw.githubusercontent.com/kieferwaight/recovery-toolkit/main/bootstrap.sh | sudo bash
```

This sets up the bare minimum to load the repo and handoff to Makefile (`make all`),
which installs packages, symlinks `bin/` into `/usr/local/bin`, and installs a
shellcheck pre-commit hook.

## Layout
- `bin/` - toolkit executables (secure erase, USB tuning, overlay boot setup)
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

See [docs/luks-layout-notes.md](docs/luks-layout-notes.md) for the plan around
LUKS key/header storage and disk identification.
