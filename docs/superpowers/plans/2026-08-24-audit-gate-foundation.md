# Audit Gate Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add validated recovery-network profiles and a vault-backed, fail-closed audit gate for destructive disk commands.

**Architecture:** Keep profile parsing and audit policy in focused shared shell libraries. The audit library validates the configured vault mount, captures stable target identity through `lsblk`/`udevadm`/`blkid`, writes pre-operation and completion records, and never writes secret material. Secure-erase commands call the gate before touching a target and record the final result.

**Tech Stack:** Bash, POSIX command-line tools available on Ubuntu, existing `lib/common.sh`, fixture-based shell tests, ShellCheck.

**Spec:** `docs/superpowers/specs/2026-08-24-encrypted-host-provisioning-design.md`

## Global Constraints

- Plaintext LUKS key material and private keys must not enter Git, `.env`, logs, or the operating USB.
- Destructive operations require explicit target confirmation.
- A failed or interrupted operation must never be represented as successful.
- The vault must be identified by filesystem UUID, not `/dev/sdX`.
- MAC matching is diagnostic only and is never the authorization mechanism.
- Use ASCII for new files and preserve the existing Bash/ShellCheck style.
- Do not modify live disks while developing or testing this slice.

### Task 1: Define Recovery Profile Validation

**Files:**
- Create: `lib/recovery_profile.sh`
- Modify: `lib/common.sh`
- Modify: `.env.example`
- Modify: `tests/test_setup_commands.sh`
- Test: `tests/test_recovery_profile.sh`

**Interfaces:**
- Consumes: `.env` values loaded by `load_env`.
- Produces: `load_recovery_profile`, `validate_recovery_profile`, and exported variables `RECOVERY_INTERFACE`, `RECOVERY_GATEWAY`, `RECOVERY_HOST_IP`, `RECOVERY_SUBNET`, `RECOVERY_SSH_PORT`, and optional `RECOVERY_CLIENT_CIDR`.

- [x] **Step 1: Write failing profile tests**

Create a temporary environment fixture and test that a valid profile passes, a
host address outside the subnet fails, a gateway outside the subnet fails, an
invalid port fails, and a missing interface fails only when live validation is
requested. Use shell functions and temporary files; do not require root or a
network device for syntax-only tests.

- [x] **Step 2: Run the profile tests and verify failure**

Run:

```bash
bash tests/test_recovery_profile.sh
```

Expected: FAIL because `lib/recovery_profile.sh` and its validation functions
do not exist.

- [x] **Step 3: Implement the profile library**

Add strict IPv4/CIDR validation using Bash regular expressions plus numeric
octet checks. Validate that gateway and host are in the same `/24` subnet, the
host is not the network, broadcast, or gateway address, and the port is `1`
through `65535`. Keep interface existence as a separate `validate_recovery_interface`
function so fixture tests remain offline.

- [x] **Step 4: Add profile defaults and common loading**

Source the new library from `lib/common.sh` only after existing helpers are
defined. Add commented empty defaults to `.env.example` and ensure an empty
profile remains acceptable to existing commands that do not use initramfs
networking.

- [x] **Step 5: Run profile tests and static checks**

Run:

```bash
bash tests/test_recovery_profile.sh
make check
```

Expected: PASS with no ShellCheck findings.

- [x] **Step 6: Commit the profile slice**

```bash
git add lib/common.sh lib/recovery_profile.sh .env.example tests/test_recovery_profile.sh tests/test_setup_commands.sh
git commit -m "Add recovery network profile validation"
```

### Task 2: Add Vault-Backed Audit Primitives

**Files:**
- Create: `lib/audit.sh`
- Modify: `.env.example`
- Create: `tests/test_audit.sh`

**Interfaces:**
- Consumes: `VAULT_UUID`, `VAULT_MOUNTPOINT`, `VAULT_SUBDIR`, `REAL_USER`, and common logging helpers.
- Produces: `require_audit_vault`, `audit_target_identity`, `audit_begin`, and `audit_finish`.

- [x] **Step 1: Write failing audit tests**

Test with command stubs and temporary directories that:

```bash
require_audit_vault
```

fails when the configured mountpoint is absent, succeeds only when the mount
source resolves to the configured UUID, and rejects a non-writable audit
directory. Test that `audit_begin` creates a record with operation ID, UTC
timestamps, action, target identity, and `status=planned`, while excluding
environment values whose names contain `KEY`, `SECRET`, `PASSWORD`, or `TOKEN`.

- [x] **Step 2: Run the audit tests and verify failure**

Run:

```bash
bash tests/test_audit.sh
```

Expected: FAIL because the audit library is not implemented.

- [x] **Step 3: Implement vault validation**

Resolve the configured UUID through `/dev/disk/by-uuid`, compare the mounted
source using `findmnt`, require the mountpoint to be a mountpoint, create the
host audit directory under `${VAULT_MOUNTPOINT}/${VAULT_SUBDIR}/hosts`, and
require a write-and-remove probe before proceeding. Never fall back to the OS
USB when the vault is unavailable.

- [x] **Step 4: Implement target identity capture**

Use `lsblk --json`, `udevadm info --query=property`, and `blkid` where
available. Serialize model, serial, WWN, size, sector size, transport,
kernel device, partition table identifiers, filesystem UUID, and LUKS UUID as
plain metadata. If a stable identity cannot be captured, fail closed for
destructive operations.

- [x] **Step 5: Implement begin/finish records**

Write records atomically through a temporary file in the vault directory and
rename them into place. `audit_begin` must write `planned` before the caller
touches the target. `audit_finish` must accept an explicit numeric exit status
and write `completed` only for status zero; all other values write `failed`.

- [x] **Step 6: Run audit tests and static checks**

Run:

```bash
bash tests/test_audit.sh
make check
```

Expected: PASS with no ShellCheck findings.

- [x] **Step 7: Commit the audit slice**

```bash
git add lib/audit.sh .env.example tests/test_audit.sh
git commit -m "Add vault-backed audit primitives"
```

### Task 3: Integrate the Audit Gate Into Secure Erase

**Files:**
- Modify: `bin/hdd-secure-erase`
- Modify: `bin/ssd-secure-erase`
- Modify: `bin/nvme-secure-erase`
- Modify: `lib/common.sh`
- Modify: `tests/test_setup_commands.sh`
- Create: `tests/test_secure_erase_audit.sh`
- Modify: `docs/hdd-secure-erase.md`
- Modify: `docs/ssd-secure-erase.md`
- Modify: `docs/nvme-secure-erase.md`

**Interfaces:**
- Consumes: `require_audit_vault`, `audit_target_identity`, `audit_begin`, and `audit_finish` from `lib/audit.sh`.
- Produces: secure-erase commands that fail before device mutation when audit prerequisites are unavailable and record every attempted operation.

- [x] **Step 1: Write failing integration tests**

Stub destructive utilities and assert each secure-erase command refuses to call
them when the vault is absent. Add a success fixture proving the stub utility
is called only after a `status=planned` record exists. Add failure fixtures for
the destructive utility returning nonzero and verify the audit record is
`failed`, not `completed`.

- [x] **Step 2: Run integration tests and verify failure**

Run:

```bash
bash tests/test_secure_erase_audit.sh
```

Expected: FAIL because the existing commands do not call the audit gate.

- [x] **Step 3: Add the shared audit invocation**

Source `lib/audit.sh` through the existing script path resolution. After target
argument validation and before any erase capability probe that can mutate
device state, capture identity and call `audit_begin`.

- [x] **Step 4: Record command outcomes safely**

Run the existing erase operation with `set +e` only around the destructive
command, capture its status, call `audit_finish`, restore strict mode, and exit
with the original status. Preserve current target safety checks and warnings.

- [x] **Step 5: Update command documentation**

Document the vault prerequisite, the pre/post audit lifecycle, the fact that
plaintext keys are never logged, and the explicit target confirmation required
before erasure.

- [x] **Step 6: Run the complete verification suite**

Run:

```bash
bash tests/test_setup_commands.sh
bash tests/test_recovery_profile.sh
bash tests/test_audit.sh
bash tests/test_secure_erase_audit.sh
make test
make check
git diff --check
```

Expected: all tests pass, ShellCheck passes, and no live device is touched.

- [x] **Step 7: Commit the integration slice**

```bash
git add bin lib tests docs
git commit -m "Fail closed on unaudited disk erasure"
```

### Task 4: Live Non-Destructive Verification

**Files:**
- Modify: `docs/superpowers/plans/2026-08-24-audit-gate-foundation.md`

- [x] **Step 1: Verify vault identity on `recovery`**

Confirm the configured UUID is mounted at `/mnt/Vault`, verify the audit
directory is writable, and record only a harmless read-only inspection of the
OS USB and the separate vault device.

- [x] **Step 2: Verify fail-closed behavior**

Temporarily unmount the vault without changing its contents, invoke a secure
erase command against a non-target fixture or dry-run path, and confirm it
refuses before invoking any destructive utility. Remount the vault and verify
the operation remains represented as refused/failed rather than successful.

- [x] **Step 3: Verify no secrets escaped**

Search the repository, live toolkit directory, and audit records for private-key
headers, LUKS key contents, and secret environment variable values. The check
must find none.

- [x] **Step 4: Commit verification notes**

```bash
git add docs/superpowers/plans/2026-08-24-audit-gate-foundation.md
git commit -m "Verify audit gate on recovery host"
```

## Follow-up Plans

After this plan is complete, create separate plans for:

1. Disk sanitization capability detection and LUKS2/LVM/XFS provisioning.
2. Vault key/header lifecycle and evidence manifests.
3. Dropbear initramfs networking, forced unlock key, and recovery-client CIDR.
4. Safe overlay boot integration and USB snapshot procedure.

## Self-Review

- Profile requirements are covered by Task 1.
- Vault-backed fail-closed auditing is covered by Tasks 2 and 3.
- Destructive operations preserve explicit confirmation and target safety.
- LUKS/XFS, Dropbear, and overlay boot are intentionally excluded from this
  foundation plan and listed as follow-up plans.
- No unresolved TODO/TBD placeholders are present; path and variable names are
  concrete.

## Verification Evidence

- `make test`, `make check`, and `git diff --check` pass locally.
- The verified revision was deployed to `recovery` at `ebc1e2d`.
- With `/mnt/Vault` unmounted, `hdd-secure-erase /dev/sdd1` refused after
  confirmation and returned nonzero before invoking an erase utility.
- The vault remounted from UUID `da868d4d-9d3b-4bc8-b2a0-dd49b3b63671`.
- A read-only `/dev/sdd1` inspection produced a completed audit record under
  `/mnt/Vault/recovery-toolkit-vault/hosts/recovery/` without secret-like
  content.
