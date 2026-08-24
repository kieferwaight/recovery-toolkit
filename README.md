# Recovery Toolkit

After a fresh install of ubuntu on a portable usb, you can install the toolkit with
```
curl -fsSL https://raw.githubusercontent.com/kieferwaight/recovery-toolkit/main/bootstrap.sh | sudo bash
```

This loads the repo and runs the explicit installation targets for the recovery
USB. `make install` installs only host-facing commands; `make usb-install`
installs the packages used by the USB environment. Run `make all` afterward if
you also want the shellcheck pre-commit hook.

## Layout
- `bin/` - installed host-facing commands for disk deployment and recovery
- `scripts/usb/` - non-installed recovery USB maintenance scripts
- `setup-ssh`, `setup-tailscale` - USB maintenance targets invoked through `make usb-*`
- `install-ubuntu-server` - runs the guarded Ubuntu Server Subiquity handoff on a prepared host disk
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

The recovery USB is already protected by its own boot-time encryption prompt.
That manual unlock is separate from the host's future remote initramfs unlock
service. To reach the running USB over the Tailnet, use:

```bash
ssh kwaight@recovery
```

USB changes are intentionally not PATH commands. Review the active USB root
and vault identity first, then use an explicit Makefile target:

```bash
sudo make usb-preflight
sudo make usb-install       # one-time package/bootstrap setup
sudo make usb-vault         # only when changing vault integration
sudo make usb-ssh
sudo make usb-tailscale
sudo make usb-optimize
sudo make usb-overlay
```

The Makefile prints the active root source/UUID and configured vault
source/UUID before USB maintenance. `RECOVERY_USB_ROOT_UUID` can be set in
`.env` to require an exact root UUID match. `VAULT_UUID` must identify a
different physical disk; the vault-setup target is the only USB target that
can proceed while the vault is not currently mounted.

For the USB network setup, use the Makefile targets above:

```bash
sudo make usb-ssh
sudo make usb-tailscale
```

The USB SSH script installs and enables OpenSSH, then adds the current
`kieferwaight` GitHub public keys to the invoking user's `authorized_keys`
without duplicating existing entries. The USB Tailscale script installs and enables
Tailscale; when authorization is needed, it prints the browser URL to open.

For a RAM-first utility profile on the recovery USB itself, run:

```bash
sudo make usb-optimize
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
Configure its filesystem UUID in `.env` and run `sudo make usb-vault`; after that,
connecting and unlocking the matching vault automatically mounts it at
`/mnt/Vault` and creates `/mnt/Vault/recovery-toolkit-vault` with private
permissions.

See [docs/luks-layout-notes.md](docs/luks-layout-notes.md) for the host
provisioning plan around LUKS key/header storage and disk identification.

For the initramfs unlock workflow on the host, see
[docs/superpowers/specs/2026-08-24-encrypted-host-provisioning-design.md](docs/superpowers/specs/2026-08-24-encrypted-host-provisioning-design.md)
and the host-targeted `setup-initramfs-unlock --target-root MOUNT` command.
It never writes the running USB's `/etc`, `/boot`, or initramfs.

Before any provisioning or erase workflow, inspect a target by stable identity:

```bash
sudo inspect-disk /dev/disk/by-id/...
```

The command is read-only and prints a fingerprint based on the device's model,
serial, WWN, transport, size, and filesystem identifiers.

After the disk is sanitized and the LUKS2/LVM/XFS layout is prepared, configure
the vault-backed identity and LUKS key paths in `.env` and run:

```bash
sudo install-ubuntu-server --target /dev/disk/by-id/...
sudo install-ubuntu-server --target /dev/disk/by-id/... --apply
```

The command starts Subiquity with `--autoinstall` from the currently booted
Ubuntu Server environment and uses its mounted installer source, normally
`/cdrom`. It writes the generated configuration and evidence under the vault,
does not rebuild or modify the recovery USB, and leaves initramfs finalization
to the next host-targeted step.

Set `UBUNTU_IDENTITY_FILE` to a vault file with mode `0600` containing the
non-secret username, a crypt password hash, and the host administrator public
key:

```dotenv
UBUNTU_USERNAME=operator
UBUNTU_PASSWORD_HASH=<crypt-password-hash>
UBUNTU_SSH_PUBLIC_KEY=ssh-ed25519 AAAA... operator
```

Set `UBUNTU_LUKS_KEY_FILE` to the LUKS key generated by `provision-luks` under
the same vault. The identity file's administrator key is separate from the
restricted initramfs unlock key.
