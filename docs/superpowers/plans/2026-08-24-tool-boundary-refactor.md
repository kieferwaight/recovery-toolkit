# Recovery Tool Boundary Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Separate recovery-USB maintenance from host-facing provisioning so USB mutations require an explicit Makefile path while every host command rejects the active root and vault disks.

**Architecture:** Host operations remain executable `bin/` commands and are installed into `/usr/local/bin`. USB maintenance moves to non-installed `scripts/usb/` scripts that require a Makefile-provided context and a root/vault identity preflight. Shared libraries own protected-device resolution, logging, vault events, and key material; the initramfs renderer stays pure while a host-target installer writes only below an explicit mounted target root.

**Tech Stack:** POSIX-compatible Bash, GNU Make, `lsblk`, `findmnt`, `blkid`, `mountpoint`, `update-initramfs`, existing shell fixture tests, and ShellCheck.

**Spec:** `docs/superpowers/specs/2026-08-24-encrypted-host-provisioning-design.md`

## Global Constraints

- Recovery USB boot media is never rebuilt or modified during host provisioning.
- The USB's boot-time passphrase protects the USB itself; host Dropbear unlock is a separate host-only configuration.
- `bin/` contains only host-facing commands; `scripts/usb/` contains USB-mutating commands and is not installed into `PATH`.
- `make install` installs host-facing commands only; USB setup requires explicit `make usb-*` targets.
- Host disk commands reject the active root disk and the configured vault disk, including their physical parent disks.
- Vault writes use the shared audit path and never place plaintext key material in logs, `.env`, Git, or the USB root filesystem.
- `setup-initramfs-unlock` requires an explicit mounted host root and never targets `/`.
- All shell changes pass ShellCheck and the full `make check && make test` suite.

---

### Task 1: Lock the repository boundary in documentation and tests

**Files:**
- Modify: `README.md`
- Modify: `.env.example`
- Modify: `docs/TODO.md`
- Modify: `docs/superpowers/specs/2026-08-24-encrypted-host-provisioning-design.md`
- Create: `tests/test_tool_boundary.sh`
- Modify: `Makefile`

**Interfaces:**
- Produces the command classification and Makefile target names used by later tasks.
- Produces fixture assertions that fail if USB scripts are installed or if USB commands remain in `bin/`.

- [ ] **Step 1: Write failing boundary assertions**

Add a shell fixture test that asserts:

```bash
host_commands='inspect-disk hdd-secure-erase nvme-secure-erase provision-luks setup-initramfs-unlock ssd-secure-erase install-ubuntu-server'
usb_commands='optimize-usb setup-overlay-boot setup-ssh setup-tailscale setup-vault'
for command in ${host_commands}; do test -f "${repo_dir}/bin/${command}"; done
for command in ${usb_commands}; do test -f "${repo_dir}/scripts/usb/${command}"; done
for command in ${usb_commands}; do test ! -e "${repo_dir}/bin/${command}"; done
grep -Fq 'usb-preflight' "${repo_dir}/Makefile"
grep -Fq 'usb-install' "${repo_dir}/Makefile"
grep -Fq 'RECOVERY_DISK_UUID' "${repo_dir}/Makefile"
grep -Fq 'VAULT_UUID' "${repo_dir}/Makefile"
```

Also assert that `make install` iterates only over `bin/*`, that the Makefile
has explicit `usb-*` targets, and that the documentation says initramfs
configuration targets the host root.

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
./tests/test_tool_boundary.sh
```

Expected: FAIL because USB commands are still under `bin/` and the Makefile
does not yet expose the USB maintenance boundary.

- [ ] **Step 3: Update the boundary documentation and Makefile contract**

Document these commands:

```text
make install       install host-facing commands only
make usb-preflight display and validate USB root/vault identity context
make usb-install   perform one-time USB package/bootstrap installation
make usb-vault     configure the USB vault mount integration
make usb-ssh       configure SSH on the recovery USB
make usb-tailscale configure Tailscale on the recovery USB
make usb-optimize  apply the disposable USB optimization profile
make usb-overlay   configure the optional USB overlay boot profile
```

Add `RECOVERY_USB_ROOT_UUID` as an optional strict expected UUID. When set,
the detected root UUID must match it; `VAULT_UUID` must be present for USB
maintenance targets, and the two UUIDs must differ. Keep `RECOVERY_DISK_UUID`
as a compatibility alias only if existing profile validation requires it, and
make the Makefile use one canonical value internally.

- [ ] **Step 4: Run the focused test and verify it passes**

Run:

```bash
./tests/test_tool_boundary.sh
```

Expected: PASS for the documented target names and the Makefile installation
contract.

- [ ] **Step 5: Commit the boundary contract**

```bash
git add README.md .env.example docs/TODO.md docs/superpowers/specs/2026-08-24-encrypted-host-provisioning-design.md tests/test_tool_boundary.sh Makefile
git commit -m "Define USB and host tool boundaries"
```

### Task 2: Add protected-device and USB-context safety libraries

**Files:**
- Create: `lib/device_guard.sh`
- Create: `lib/usb_context.sh`
- Modify: `lib/common.sh`
- Modify: `.env.example`
- Modify: `Makefile`
- Test: `tests/test_tool_boundary.sh`
- Create: `tests/test_device_guard.sh`

**Interfaces:**
- `device_guard.sh` provides `protected_disk_for_source`, `assert_not_protected_disk`, and `assert_target_root_is_safe`.
- `usb_context.sh` provides `usb_context_report`, `usb_require_make_context`, and `usb_validate_context`.
- Host commands source `device_guard.sh`; USB scripts source `usb_context.sh`.

- [ ] **Step 1: Write failing device and context fixtures**

Use command stubs in temporary `PATH` to model a root source, vault source,
partitions, and physical disks. Assert that `assert_not_protected_disk` rejects
both the root disk and the vault disk, rejects their partitions, and accepts a
separate target. Assert that `usb_require_make_context` rejects direct
execution and accepts the exact Makefile marker plus a valid target name.

The fixture must not call `dd`, `wipefs`, `sgdisk`, `cryptsetup`, `mount`, or
`update-initramfs`.

- [ ] **Step 2: Run the focused fixtures and verify they fail**

```bash
./tests/test_device_guard.sh
./tests/test_tool_boundary.sh
```

Expected: FAIL because the new helpers do not exist.

- [ ] **Step 3: Implement physical-disk resolution and fail-closed checks**

Implement `device_guard.sh` so every source resolves to its physical `TYPE=disk`
ancestor using `lsblk -s`. If the active root or vault source cannot resolve to
a physical disk, return an error instead of allowing a target. Compare the
physical target against every protected physical disk, not only the exact
filesystem path. `assert_target_root_is_safe` must reject `/`, the configured
vault mount, and any target root that is not an absolute mounted directory.

Keep `common.sh` responsible for loading `.env` and logging; source the focused
guard from host commands rather than duplicating device logic.

- [ ] **Step 4: Implement the Makefile-only USB context**

`usb_context.sh` must:

1. Resolve the active root source and filesystem UUID.
2. Resolve its physical disk and print source, UUID, and disk.
3. Resolve `VAULT_UUID` when present and print its device, filesystem UUID, and physical disk.
4. Refuse matching root/vault disks or matching UUIDs.
5. Refuse a configured `RECOVERY_USB_ROOT_UUID` mismatch.
6. Require `RECOVERY_USB_MAKE_CONTEXT=1` and an allowlisted `RECOVERY_USB_MAKE_TARGET` for mutating USB scripts.

The Makefile must pass the marker and target explicitly through `sudo env`.
No USB script is symlinked into `/usr/local/bin`.

- [ ] **Step 5: Run focused fixtures and repository checks**

```bash
./tests/test_device_guard.sh
./tests/test_tool_boundary.sh
shellcheck -x -P lib lib/device_guard.sh lib/usb_context.sh
```

Expected: PASS.

- [ ] **Step 6: Commit the safety libraries**

```bash
git add lib/common.sh lib/device_guard.sh lib/usb_context.sh .env.example Makefile tests/test_device_guard.sh tests/test_tool_boundary.sh
git commit -m "Add protected disk and USB context guards"
```

### Task 3: Move USB maintenance behind explicit Makefile targets

**Files:**
- Move: `bin/optimize-usb` -> `scripts/usb/optimize-usb`
- Move: `bin/setup-overlay-boot` -> `scripts/usb/setup-overlay-boot`
- Move: `bin/setup-ssh` -> `scripts/usb/setup-ssh`
- Move: `bin/setup-tailscale` -> `scripts/usb/setup-tailscale`
- Move: `bin/setup-vault` -> `scripts/usb/setup-vault`
- Move: `packages/setup-packages.sh` -> `scripts/usb/install-packages`
- Modify: `Makefile`
- Modify: `bootstrap.sh`
- Modify: `tests/test_setup_commands.sh`
- Modify: `tests/test_tool_boundary.sh`
- Modify: `docs/setup-overlay-boot.md`
- Modify: `docs/luks-layout-notes.md`

**Interfaces:**
- Each moved script remains a shell entrypoint for its one USB action but must source `../../lib/common.sh` and `../../lib/usb_context.sh`.
- Each script calls `usb_require_make_context` before mutating the running USB.
- Makefile targets call the matching script with `RECOVERY_USB_MAKE_TARGET=$@`.

- [ ] **Step 1: Extend tests for the moved scripts**

Change existing static assertions to point at `scripts/usb/`. Add assertions
that each script calls `usb_require_make_context`, that no USB script appears
in the symlink loop, and that direct `bash scripts/usb/setup-vault` exits before
writing `/etc` when the Makefile marker is absent.

- [ ] **Step 2: Run the focused tests and verify they fail**

```bash
./tests/test_setup_commands.sh
./tests/test_tool_boundary.sh
```

Expected: FAIL because the scripts have not moved and do not have the USB
context guard.

- [ ] **Step 3: Move and adapt the scripts**

Move the five scripts under `scripts/usb/`, update their library paths, and
call `usb_require_make_context` immediately after loading the environment and
before any package, systemd, `/etc`, or boot-file mutation. Keep the scripts
non-installed and invoke them with `bash` from Make targets.

- [ ] **Step 4: Add explicit Makefile targets and stale-link cleanup**

Make `install` depend on `env` and host-only symlinks; it must not call the
USB package installer. Make `usb-install` call only
`scripts/usb/install-packages`, after the same USB context preflight as other
USB mutations.
Make its symlink loop iterate only over the allowlisted host command files.
Remove stale symlinks only when they are symbolic links pointing to this
repository's former `bin/` USB paths. Add explicit `usb-preflight` and one
target for each moved script. `usb-install` must be the only target that calls
the USB package installer. Update `bootstrap.sh` to call `make install` and
then `make usb-install`, so a fresh USB still receives its packages without
making the normal host-tool installation target ambiguous.

- [ ] **Step 5: Run tests and shellcheck**

```bash
./tests/test_setup_commands.sh
./tests/test_tool_boundary.sh
make check
```

Expected: PASS, with no USB script installed into `/usr/local/bin`.

- [ ] **Step 6: Commit the USB maintenance boundary**

```bash
git add Makefile scripts/usb bin tests/test_setup_commands.sh tests/test_tool_boundary.sh docs/setup-overlay-boot.md docs/luks-layout-notes.md
git commit -m "Gate USB maintenance through Makefile"
```

### Task 4: Centralize key material staging and audited vault events

**Files:**
- Create: `lib/key_material.sh`
- Modify: `lib/common.sh`
- Modify: `lib/audit.sh`
- Modify: `bin/provision-luks`
- Modify: `bin/install-ubuntu-server`
- Modify: `.env.example`
- Create: `tests/test_key_material.sh`
- Modify: `tests/test_provision_luks.sh`
- Modify: `tests/test_ubuntu_install.sh`

**Interfaces:**
- `key_material.sh` provides `create_runtime_key`, `copy_secret_to_runtime`, `secret_sha256`, and `cleanup_runtime_secret`.
- `audit.sh` provides `audit_vault_path` and `audit_record_event` for vault writes under the operation directory.
- Provisioning and installer commands use these helpers and do not redefine temporary-key paths or direct vault event directories.

- [ ] **Step 1: Write failing key and vault-event tests**

Assert that runtime key files are created below `/dev/shm` with mode `0600`,
that the helper returns only a checksum when requested, that cleanup removes
the file, and that plaintext contents are absent from captured logger output.
Assert that `audit_vault_path` refuses paths outside `AUDIT_ROOT` and that
`audit_record_event` creates mode `0600` event records below the active
operation directory.

- [ ] **Step 2: Run focused tests and verify they fail**

```bash
./tests/test_key_material.sh
./tests/test_provision_luks.sh
./tests/test_ubuntu_install.sh
```

Expected: FAIL because the focused helpers do not exist.

- [ ] **Step 3: Implement the helpers**

Use `dd if=/dev/urandom` for generated LUKS material, `mktemp /dev/shm/...`
for runtime staging, `install -m 0600` for copies, and traps for cleanup.
Never print key contents. Make vault event paths derive from `AUDIT_ROOT` and
reject traversal or absolute paths supplied by a command.

- [ ] **Step 4: Refactor provisioning and installer commands**

Replace inline key creation/copy/cleanup and direct evidence path construction
with the shared helpers. Preserve existing dry-run defaults, target fingerprint
confirmation, audit begin/finish, and installer behavior.

- [ ] **Step 5: Run focused tests and commit**

```bash
./tests/test_key_material.sh
./tests/test_provision_luks.sh
./tests/test_ubuntu_install.sh
git add lib/key_material.sh lib/common.sh lib/audit.sh bin/provision-luks bin/install-ubuntu-server .env.example tests/test_key_material.sh tests/test_provision_luks.sh tests/test_ubuntu_install.sh
git commit -m "Centralize key staging and vault events"
```

### Task 5: Make initramfs unlock host-targeted

**Files:**
- Modify: `bin/setup-initramfs-unlock`
- Modify: `lib/initramfs_unlock.sh`
- Modify: `.env.example`
- Modify: `tests/test_initramfs_unlock.sh`
- Create: `tests/test_initramfs_target.sh`
- Modify: `README.md`
- Modify: `docs/TODO.md`

**Interfaces:**
- `bin/setup-initramfs-unlock` accepts `--target-root ABSOLUTE_MOUNTPOINT`, `--dry-run`, and `--apply`; no target-root default is allowed.
- `initramfs_unlock_target_paths TARGET_ROOT` returns target-scoped config, authorized-key, and initramfs paths.
- `install_initramfs_unlock_target TARGET_ROOT` writes the restricted files below the target and invokes `chroot TARGET_ROOT update-initramfs -u -k all` only after target validation.

- [ ] **Step 1: Write failing target-root tests**

Create a temporary target tree with `etc`, `boot`, and a mocked `update-initramfs`.
Assert that dry-run prints the target paths without writing the USB or target,
that apply writes only `${target_root}/etc/dropbear-initramfs/`, and that the
mocked rebuild is invoked with `chroot ${target_root} update-initramfs -u -k all`.
Assert refusal for missing `--target-root`, `/`, the configured vault mount,
an unmounted directory, and a target whose source is the active USB disk.
Assert that the forced key contains `command="cryptroot-unlock"` and no shell
forwarding features.

- [ ] **Step 2: Run the focused tests and verify they fail**

```bash
./tests/test_initramfs_target.sh
./tests/test_initramfs_unlock.sh
```

Expected: FAIL because the command currently writes the running USB's `/etc`
and has no target-root interface.

- [ ] **Step 3: Implement target path validation and rendering**

Keep `initramfs_unlock_dropbear_config` and
`initramfs_unlock_authorized_key` pure. Add target path derivation that joins
validated relative paths to the target root without allowing an absolute
override to escape it. Require the target root to be a mountpoint whose
source is a block-backed filesystem distinct from the active root and vault.

- [ ] **Step 4: Implement the host-targeted command**

Default to dry-run. On `--apply`, require root, the valid profile, the mounted
target root, the vault audit gate, and the exact target identity confirmation.
Write Dropbear config and authorized keys with modes `0600` in the target,
then run the target's `update-initramfs` through `chroot`. Record target root,
target disk identity, key fingerprint, deployment checksum, and rebuild status
in the vault. Never call `update-initramfs` without `chroot`, and never write
the same paths under the running USB root.

- [ ] **Step 5: Run tests and commit**

```bash
./tests/test_initramfs_target.sh
./tests/test_initramfs_unlock.sh
make check
git add bin/setup-initramfs-unlock lib/initramfs_unlock.sh .env.example tests/test_initramfs_target.sh tests/test_initramfs_unlock.sh README.md docs/TODO.md
git commit -m "Target initramfs unlock at installed host root"
```

### Task 6: Complete documentation, full verification, and push

**Files:**
- Modify: `README.md`
- Modify: `docs/luks-layout-notes.md`
- Modify: `docs/TODO.md`
- Modify: `docs/superpowers/plans/2026-08-24-tool-boundary-refactor.md`
- Modify: `Makefile`

**Interfaces:**
- Documentation exposes separate USB setup and host provisioning workflows.
- The completed plan records the exact verification commands and results.

- [ ] **Step 1: Update operator documentation**

Document the safe sequence:

```text
make install
make usb-preflight
make usb-install       # only for initial USB setup
make usb-vault          # only when changing USB vault integration
inspect-disk TARGET
secure-erase TARGET
provision-luks TARGET
install-ubuntu-server TARGET --apply
mount the installed host root explicitly
setup-initramfs-unlock --target-root MOUNT --apply
```

State that `ssh kwaight@recovery` reaches the USB over the Tailnet, while the
future host Dropbear service uses the host recovery address and port `2222`.
State that inserting the USB and entering its passphrase is a separate manual
security ceremony and is not part of host remote unlock.

- [ ] **Step 2: Run the complete verification suite**

```bash
make check
make test
git diff --check
git status --short --branch
```

Expected: all checks pass, `git diff --check` is silent, and only intended
commits are present on the branch.

- [ ] **Step 3: Review the final boundary statically**

```bash
find bin -maxdepth 1 -type f -print | sort
find scripts/usb -maxdepth 1 -type f -print | sort
rg -n 'scripts/usb|usb-preflight|RECOVERY_USB_MAKE_CONTEXT|target-root|update-initramfs' Makefile bin lib scripts README.md docs tests
```

Confirm that `bin/` contains no USB-only command, no USB script is linked by
the install loop, and no initramfs command can update the running USB root.

- [ ] **Step 4: Commit documentation and push**

```bash
git add README.md docs/luks-layout-notes.md docs/TODO.md docs/superpowers/plans/2026-08-24-tool-boundary-refactor.md Makefile
git commit -m "Document safe USB and host workflows"
git push origin main
```
