# Ubuntu Server Installation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a guarded host-install command that uses the already booted Ubuntu Server environment's Subiquity autoinstall path to populate a pre-created LUKS2/LVM/XFS target without modifying the recovery USB.

**Architecture:** `lib/ubuntu_install.sh` owns installer-profile parsing, identity-file parsing, validation, and deterministic autoinstall YAML rendering. `bin/install-ubuntu-server` performs read-only discovery by default, writes rendered configuration and audit evidence only under the mounted vault on `--apply`, then invokes `subiquity --autoinstall` after a second target identity read and exact fingerprint confirmation. The generated storage graph preserves the existing disk, partitions, LUKS container, VG, LV, and XFS root; only EFI and `/boot` filesystems are formatted by the installer.

**Tech Stack:** Bash, Subiquity autoinstall YAML, Curtin storage actions, existing vault/audit/profile libraries, ShellCheck, fixture-based shell tests.

**Spec:** `docs/superpowers/specs/2026-08-24-encrypted-host-provisioning-design.md`

## Global Constraints

- Recovery USB boot media is never rebuilt or modified by this workflow.
- `install-ubuntu-server` is read-only by default; target changes require `--apply`, the vault audit gate, and exact target fingerprint confirmation.
- The target is selected by a stable `/dev/disk/by-id/...` path and must not be the active boot disk or configured vault device.
- The installer source is the currently booted Ubuntu Server installation source, normally `/cdrom`; the command does not use `debootstrap`.
- LUKS key contents never appear in YAML, logs, Git, or `.env`; the vault key is staged into RAM and YAML may contain only the ephemeral runtime `keyfile` path.
- Generated installer configuration and evidence use mode `0600` below `${VAULT_MOUNTPOINT}/${VAULT_SUBDIR}/hosts/${HOST_ID}/installer/`.
- No reboot is invoked by the toolkit command; final power-state handling remains with the operator.

---

### Task 1: Define the vault-backed installer profile and renderer

**Files:**
- Create: `lib/ubuntu_install.sh`
- Modify: `.env.example`
- Modify: `packages/base.apt.list`
- Test: `tests/test_ubuntu_install.sh`

**Interfaces:**
- Consumes: `load_provision_profile`, `disk_identity_value`, and the existing recovery/audit profile conventions.
- Produces: `load_ubuntu_install_profile`, `validate_ubuntu_install_profile`, `load_ubuntu_identity_file`, `validate_ubuntu_identity`, and `render_ubuntu_autoinstall`.

- [x] **Step 1: Write the failing test**

Create a fixture-driven shell test that sources `lib/ubuntu_install.sh` and
sets these values:

```bash
export HOST_ID='slinky'
export TARGET_DISK='/dev/disk/by-id/wwn-test'
export UBUNTU_INSTALLER_SOURCE='/cdrom'
export UBUNTU_IDENTITY_FILE="${tmp_dir}/identity.env"
export UBUNTU_LUKS_KEY_FILE='/mnt/Vault/recovery-toolkit-vault/hosts/slinky/provisioning/op/luks/luks.key'
cat >"${UBUNTU_IDENTITY_FILE}" <<'EOF'
UBUNTU_USERNAME=operator
UBUNTU_PASSWORD_HASH=$6$rounds=5000$example$hash
UBUNTU_SSH_PUBLIC_KEY=ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIexample operator
EOF

validate_ubuntu_install_profile
yaml="$(render_ubuntu_autoinstall 1073741824 2147483648 0 /run/recovery-luks-key)"
grep -Fq 'autoinstall:' <<<"${yaml}"
grep -Fq 'type: dm_crypt' <<<"${yaml}"
grep -Fq 'preserve: true' <<<"${yaml}"
grep -Fq 'fstype: xfs' <<<"${yaml}"
grep -Fq 'keyfile: /run/recovery-luks-key' <<<"${yaml}"
! grep -Fq 'UBUNTU_PASSWORD_HASH' <<<"${yaml}"
```

Add failures for a missing identity file, an insecure multiline key, an
inline LUKS key field, a non-absolute installer source, and an identity file
with permissions broader than `0600`.

- [x] **Step 2: Run the test to verify it fails**

Run: `./tests/test_ubuntu_install.sh`

Expected: FAIL because the profile functions and renderer do not exist.

- [x] **Step 3: Implement the minimal profile and renderer**

Add these profile defaults:

```bash
UBUNTU_INSTALLER_SOURCE="${UBUNTU_INSTALLER_SOURCE:-/cdrom}"
UBUNTU_IDENTITY_FILE="${UBUNTU_IDENTITY_FILE:-}"
UBUNTU_LUKS_KEY_FILE="${UBUNTU_LUKS_KEY_FILE:-}"
```

Parse the identity file as literal `KEY=VALUE` records without executing it.
Validate the username, crypt password hash, and one-line SSH public key. Render
an autoinstall document containing `version: 1`, the identity and SSH sections,
`shutdown: poweroff`, and action-based storage that preserves the GPT disk,
partitions, LUKS container, volume group, logical volume, and XFS root. Use the
exact EFI, `/boot`, and encrypted partition sizes supplied by disk inspection.
Format only EFI as `fat32` and `/boot` as `ext4`.

- [x] **Step 4: Run the focused test to verify it passes**

Run: `./tests/test_ubuntu_install.sh`

Expected: PASS with no plaintext password variable name or LUKS key content in
the rendered document.

- [x] **Step 5: Commit**

```bash
git add lib/ubuntu_install.sh .env.example packages/base.apt.list tests/test_ubuntu_install.sh
git commit -m "Add Ubuntu installer profile renderer"
```

### Task 2: Add the guarded Subiquity installer command

**Files:**
- Create: `bin/install-ubuntu-server`
- Modify: `Makefile`
- Modify: `tests/test_ubuntu_install.sh`
- Modify: `README.md`
- Modify: `docs/luks-layout-notes.md`

**Interfaces:**
- Consumes: `validate_ubuntu_install_profile`, `render_ubuntu_autoinstall`, `require_audit_vault`, `audit_target_identity`, `audit_begin`, `audit_finish`, and `confirm_destructive`.
- Produces: `install-ubuntu-server [--dry-run|--apply] [--target /dev/disk/by-id/...]`.

- [x] **Step 1: Write failing command-contract tests**

Assert the command contains the required guards and invocation:

```bash
grep -Fq 'subiquity' "${repo_dir}/bin/install-ubuntu-server"
grep -Fq -- '--autoinstall' "${repo_dir}/bin/install-ubuntu-server"
grep -Fq 'require_audit_vault' "${repo_dir}/bin/install-ubuntu-server"
grep -Fq 'audit_finish' "${repo_dir}/bin/install-ubuntu-server"
grep -Fq 'DRY_RUN=1' "${repo_dir}/bin/install-ubuntu-server"
! grep -Eq 'reboot|kexec' "${repo_dir}/bin/install-ubuntu-server"
```

Use command stubs to verify the dry-run path does not invoke `subiquity`,
`mount`, `cryptsetup`, `mkfs`, `sgdisk`, or `partprobe`.

- [x] **Step 2: Run the test to verify it fails**

Run: `./tests/test_ubuntu_install.sh`

Expected: FAIL because the command does not exist.

- [x] **Step 3: Implement the dry-run command**

The command loads `.env`, accepts an optional stable target override, validates
the target, rejects the boot disk and configured vault device, confirms the
installer source contains `casper/filesystem.squashfs`, reads the partition
sizes with `lsblk`, and renders the YAML to a temporary file. It prints the
target fingerprint, source path, vault evidence directory, and exact Subiquity
invocation without printing secrets. It exits before any device or installer
command in the default dry-run mode.

- [x] **Step 4: Implement the guarded apply path**

On `--apply`, require root, `require_audit_vault`, a second identity read that
matches the initial fingerprint, and the existing exact fingerprint prompt.
Copy the vault LUKS key into a `0600` file on `/dev/shm`, render the config to
the vault with mode `0600`, and set a trap to remove the temporary key and
rendered temporary config. Start `audit_begin` before invoking:

```bash
subiquity --autoinstall "${autoinstall_path}"
```

Always call `audit_finish` with the Subiquity exit status and record the config
SHA-256, installer source identity, target fingerprint, and key SHA-256 in the
vault manifest. Do not copy private or LUKS key contents into the target root.

- [x] **Step 5: Run focused and full tests**

Run: `./tests/test_ubuntu_install.sh && make check && make test && git diff --check`

Expected: PASS; no command writes outside the test fixture or vault fixture.

- [x] **Step 6: Update user documentation**

Document this order:

```bash
sudo inspect-disk /dev/disk/by-id/<target>
sudo provision-luks --target /dev/disk/by-id/<target>
sudo install-ubuntu-server --target /dev/disk/by-id/<target>
sudo install-ubuntu-server --target /dev/disk/by-id/<target> --apply
```

State that `--apply` starts Subiquity from the currently booted Ubuntu Server
environment, uses the mounted installer source, and does not modify or reboot
the recovery USB. Point the follow-up initramfs task at the installed target
root rather than the USB root.

- [x] **Step 7: Commit**

```bash
git add bin/install-ubuntu-server Makefile tests/test_ubuntu_install.sh README.md docs/luks-layout-notes.md
git commit -m "Add guarded Ubuntu Server installer command"
```

### Task 3: Repository verification and handoff

**Files:**
- Modify: `docs/TODO.md`
- Modify: `docs/superpowers/specs/2026-08-24-encrypted-host-provisioning-design.md`
- Modify: `docs/superpowers/plans/2026-08-24-ubuntu-server-installation.md`

- [x] **Step 1: Record the next dependent objective**

Replace the completed host installer item in `docs/TODO.md` with the next
dependent objective: make `setup-initramfs-unlock` operate on an explicit target
root and run `update-initramfs` without writing to the USB.

- [x] **Step 2: Verify the repository**

Run: `make check && make test && git diff --check && git status --short --branch`

Expected: all checks pass and the working tree is clean after the commits.

- [x] **Step 3: Commit and push**

```bash
git push origin main
```

Expected: `origin/main` contains the installer commits and the local branch is
up to date.
