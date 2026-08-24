# Recovery Toolkit

After a fresh install of ubuntu on a portable usb, you can install the toolkit with
```
curl -fsSL https://raw.githubusercontent.com/kieferwaight/recovery-toolkit/main/bootstrap.sh | sudo bash
```

This loads the repo and runs `make install`, which installs packages and
idempotently symlinks the `bin/` commands into `/usr/local/bin`. Run `make all`
afterward if you also want the shellcheck pre-commit hook.

## Layout
- `bin/` - toolkit executables for host deployment, vault management, and USB maintenance
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

For a RAM-first utility profile on the recovery USB itself, run:

```bash
sudo optimize-usb
```

This creates a rollback snapshot under `/root`, removes unused snap support,
disables background update/telemetry services, moves temporary paths into
tmpfs, disables swap, and bounds delayed writeback. The profile prioritizes
interactive performance and USB wear reduction over persistence; the root
filesystem may lose up to 60 seconds of recent writes after sudden power loss.
The optimizer also keeps APT lists in RAM and sets removable USB readahead to
1024 KiB. It deliberately retains `thermald` and does not enable ext4
`data=writeback` or global unsafe dpkg I/O, preserving thermal protection and
package/database integrity.

For persistent secrets and LUKS recovery material, use a separate
hardware-encrypted USB vault. Keep it out of `/etc/fstab`, verify its stable
identity before mounting, and mount it only for the operation that needs it.
Configure its filesystem UUID in `.env` and run `sudo setup-vault`; after that,
connecting and unlocking the matching vault automatically mounts it at
`/mnt/Vault` and creates `/mnt/Vault/recovery-toolkit-vault` with private
permissions.

See [docs/luks-layout-notes.md](docs/luks-layout-notes.md) for the host
provisioning plan around LUKS key/header storage and disk identification.

For the initramfs unlock workflow on the host, see
[docs/superpowers/specs/2026-08-24-encrypted-host-provisioning-design.md](docs/superpowers/specs/2026-08-24-encrypted-host-provisioning-design.md)
and the `setup-initramfs-unlock` command.

Before any provisioning or erase workflow, inspect a target by stable identity:

```bash
sudo inspect-disk /dev/disk/by-id/...
```

The command is read-only and prints a fingerprint based on the device's model,
serial, WWN, transport, size, and filesystem identifiers.
