# LUKS XFS Provisioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add a dry-run-first host provisioning command that records a target disk identity, creates a LUKS2/LVM/XFS layout, and stores recovery material in the hardware-encrypted vault.

**Architecture:** `inspect-disk` remains read-only and emits stable device metadata for selection. `provision-luks` requires the vault audit gate, a validated profile, an explicit target identity confirmation, and a `--confirm` flag before changing media; it uses an in-RAM key file during provisioning and stores the key/header backup only under the vault. All destructive stages are recorded through the existing audit lifecycle.

**Tech Stack:** Bash, `lsblk`, `udevadm`, `blkid`, `sgdisk`, `wipefs`, `cryptsetup`, `lvm2`, `mkfs.xfs`, existing audit/profile libraries.

**Spec:** `docs/superpowers/specs/2026-08-24-encrypted-host-provisioning-design.md`

## Global Constraints

- Never target the active recovery USB or the configured vault device.
- Plaintext LUKS key material exists only in RAM during provisioning and in the unlocked encrypted vault afterward.
- The default mode is read-only dry-run; destructive work requires `--confirm` and an exact identity match.
- The vault must be identified by filesystem UUID, not `/dev/sdX`.
- Every destructive stage has a planned, started, and completed/failed audit state.
- Do not run live provisioning on the current testbed during this slice.

### Task 1: Add Stable Disk Inspection

**Files:**
- Create: `bin/inspect-disk`
- Create: `lib/disk_identity.sh`
- Create: `tests/test_disk_identity.sh`
- Modify: `Makefile`
- Modify: `README.md`

**Interfaces:**
- Consumes: a block-device path or `/dev/disk/by-id` path.
- Produces: `disk_identity` metadata with model, serial, WWN, path, size,
  sector size, transport, partition table, filesystem UUID, and LUKS UUID.

- [x] **Step 1: Write failing identity tests**

Stub `udevadm`, `lsblk`, `blkid`, and `blockdev`; assert stable serial/WWN
metadata is emitted, values are single-line sanitized, and inspection refuses a
target without serial and WWN.

- [x] **Step 2: Implement `lib/disk_identity.sh`**

Add `disk_identity`, `disk_identity_value`, and `disk_identity_fingerprint`.
Use udev properties for model/serial/WWN/path/transport, `lsblk` for partition
table and filesystem type, and `blkid` for UUIDs. The fingerprint is a SHA-256
hash of normalized identity metadata and contains no secret material.

- [x] **Step 3: Implement `inspect-disk`**

Require root, validate a block device, refuse the active boot disk, print the
identity in a reviewable format, and never call a mutating command.

- [x] **Step 4: Run tests and commit**

```bash
./tests/test_disk_identity.sh
make test
make check
git add bin/inspect-disk lib/disk_identity.sh tests/test_disk_identity.sh Makefile README.md
git commit -m "Add stable disk inspection"
```

### Task 2: Add Provisioning Profile and Dry Run

**Files:**
- Modify: `.env.example`
- Create: `bin/provision-luks`
- Create: `tests/test_provision_luks.sh`
- Modify: `docs/luks-layout-notes.md`

**Interfaces:**
- Consumes: `HOST_ID`, `TARGET_DISK`, `EFI_SIZE`, `BOOT_SIZE`, `ROOT_VG`,
  `ROOT_LV`, `ROOT_FS_LABEL`, `LUKS_CIPHER`, `LUKS_KEY_SIZE`, and `LUKS_PBKDF`.
- Produces: a dry-run plan and, with `--confirm`, a provisioned GPT → LUKS2 →
  LVM → XFS layout plus vault evidence.

- [x] **Step 1: Write failing dry-run tests**

Use command stubs and a fake identity fixture to assert the default invocation
does not call `sgdisk`, `wipefs`, `cryptsetup`, `pvcreate`, `vgcreate`,
`lvcreate`, or `mkfs.xfs`. Assert missing profile values and mismatched target
identity fail before any mutating command.

- [x] **Step 2: Add profile defaults and validation**

Add empty/default values to `.env.example`:

```dotenv
HOST_ID=""
TARGET_DISK=""
EFI_SIZE="1GiB"
BOOT_SIZE="2GiB"
ROOT_VG="ubuntu-vg"
ROOT_LV="ubuntu-lv"
ROOT_FS_LABEL="ubuntu-root"
LUKS_CIPHER="aes-xts-plain64"
LUKS_KEY_SIZE="512"
LUKS_PBKDF="argon2id"
```

Require an explicit target argument or configured target, a nonempty host ID,
valid sizes, supported cipher/key/PBKDF values, and a target identity
fingerprint captured immediately before provisioning.

- [x] **Step 3: Implement dry-run planning**

Print the exact intended partition, LUKS, LVM, and XFS operations. The command
must exit successfully without touching media unless `--confirm` is present.

- [x] **Step 4: Run dry-run tests and commit**

```bash
./tests/test_provision_luks.sh
make test
make check
git add bin/provision-luks .env.example tests/test_provision_luks.sh docs/luks-layout-notes.md
git commit -m "Add dry-run LUKS provisioning workflow"
```

### Task 3: Implement Vault-Backed Provisioning

**Files:**
- Modify: `bin/provision-luks`
- Modify: `lib/audit.sh`
- Modify: `tests/test_provision_luks.sh`
- Modify: `docs/luks-layout-notes.md`

**Interfaces:**
- Consumes: `require_audit_vault`, `audit_target_identity`, `audit_begin`,
  and `audit_finish`.
- Produces: vault records under
  `hosts/<host-id>/provisioning/<operation-id>/` containing identity,
  configuration, key hash, LUKS UUID, filesystem UUID, and header checksum.

- [x] **Step 1: Add key and header test fixtures**

Stub `dd`, `cryptsetup`, `cryptsetup luksHeaderBackup`, and LVM/XFS commands;
assert the key path is under `/dev/shm`, mode `600`, removed on exit, and never
appears in captured audit output. Assert header backup and SHA-256 checksum are
written under the vault only.

- [x] **Step 2: Implement protected key lifecycle**

Create a `mktemp` key file under `/dev/shm`, set `umask 077`, fill it from
`/dev/urandom`, install an EXIT trap that removes it, and write only its
SHA-256 digest plus a restricted vault copy to the evidence directory.

- [x] **Step 3: Implement destructive stages**

After a second identity read and exact fingerprint match, record `started`,
partition the disk, create LUKS2, open it, create the VG/LV, format XFS, close
the mapper, back up the LUKS header, calculate its checksum, and write the
final manifest. Any nonzero stage exits through `audit_finish` as `failed`.

- [x] **Step 4: Verify no OS-USB secret residue**

Ensure temporary key files are removed and only non-secret audit metadata is
written under the repository. The vault evidence directory is the only
persistent destination for the key/header artifacts.

- [x] **Step 5: Run tests and commit**

```bash
./tests/test_provision_luks.sh
make test
make check
git add bin/provision-luks lib/audit.sh tests/test_provision_luks.sh docs/luks-layout-notes.md
git commit -m "Provision audited LUKS XFS layouts"
```

### Task 4: Verification and Handoff

**Files:**
- Modify: `docs/superpowers/plans/2026-08-24-luks-xfs-provisioning.md`

- [x] **Step 1: Verify live read-only discovery**

Run `inspect-disk` against the separate vault and current OS USB only for
identity output; do not pass either device to `provision-luks`.

- [x] **Step 2: Verify live refusal paths**

Prove the command refuses without the vault, refuses the active boot USB,
refuses a mismatched identity, and performs no mutating calls in default
dry-run mode.

- [x] **Step 3: Record testbed readiness**

Record the exact repository revision, package availability, and the next safe
non-production target disk required for a real provisioning test.

## Follow-up Plans

After this plan is complete, create separate plans for Dropbear initramfs
networking/unlock and safe overlay boot integration.

## Verification Evidence

- Local `make test`, `make check`, and `git diff --check` pass.
- The USB checkout is synchronized at `9cc6bc2` and its test suite passes.
- Read-only inspection of `/dev/sdd1` captured model, serial, WWN, transport,
  size, sector size, filesystem UUID, and fingerprint.
- `/dev/sdc` was explicitly rejected as the active boot USB with exit `2` after
  mapper-stack boot-device detection was hardened.
- No LUKS format, partitioning, filesystem creation, or wipe operation was
  executed; a separate non-production target is still required for that live
  verification.
