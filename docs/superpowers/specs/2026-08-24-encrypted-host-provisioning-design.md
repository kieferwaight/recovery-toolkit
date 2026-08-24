# Encrypted Host Provisioning Design

## Purpose

Recovery Toolkit will provision Ubuntu hosts from the USB while keeping the
portable operating system disposable and making the separate hardware-encrypted
vault the system of record for recovery material and operational evidence.

The first complete test target is `slinky`, whose wired recovery network is
DHCP-backed but reserved as `10.0.40.2` on `10.0.40.0/24`.

## Goals

- Install Ubuntu Server onto a selected host root disk.
- Sanitize historical data on the selected disk using the safest supported
  method for its media type.
- Create a LUKS2 encryption layout with XFS filesystems inside LVM.
- Generate high-entropy LUKS material without storing plaintext keys in Git,
  `.env`, logs, or the operating USB.
- Configure Dropbear in the host initramfs on TCP port `2222`.
- Permit initramfs unlock only through the wired recovery interface and a
  restricted SSH public key.
- Track disk identities, LUKS/filesystem UUIDs, key fingerprints, header
  backups, and SSH deployment records in the vault.
- Make destructive operations fail closed when an auditable vault record cannot
  be written.
- Produce a repeatable evidence bundle suitable for later review and backup.

## Non-goals

- Treating a DHCP address or MAC address as authentication.
- Storing private keys or LUKS keys in the repository or the OS USB.
- Automatically wiping a disk without an explicit target confirmation.
- Assuming overwrite can erase hidden SSD/NVMe overprovisioned blocks.
- Implementing the RAM overlay boot mode before the provisioning and recovery
  workflow is tested.
- Rebuilding or modifying the recovery USB installer media during host
  installation.
- Replacing Ubuntu Server's Subiquity/Curtin installer with `debootstrap`.

## Recovery network profiles

Each host gets a profile containing:

```dotenv
RECOVERY_INTERFACE="enp1s0f0"
RECOVERY_GATEWAY="10.0.40.1"
RECOVERY_HOST_IP="10.0.40.2"
RECOVERY_SUBNET="10.0.40.0/24"
RECOVERY_SSH_PORT="2222"
RECOVERY_CLIENT_CIDR=""
```

The initramfs requests DHCP, then validates that the assigned address and
gateway match the profile. A mismatch disables the unlock service rather than
exposing Dropbear on an unexpected network.

`RECOVERY_CLIENT_CIDR` is optional defense in depth. When set, the initramfs
firewall permits TCP `2222` only from that CIDR. The gateway address is not
implicitly treated as the recovery client.

The profile also records the expected host MAC as inventory metadata. MAC
matching is diagnostic and is never the authorization mechanism.

## LUKS and filesystem layout

The target layout is:

```text
EFI system partition
unencrypted /boot
LUKS2 container
  LVM physical volume
    root LV -> XFS
    optional data LV -> XFS
```

The exact partition sizes and LV names are profile inputs. The toolkit records
the partition table, LUKS UUID, LVM UUIDs, filesystem UUIDs, labels, and mount
mapping after creation.

Plaintext LUKS key material is generated with the operating system CSPRNG,
used only through a protected temporary file or file descriptor, and placed in
the vault only inside a restricted directory. The vault record contains a key
identifier and checksum, not a plaintext key in the repository or normal
toolkit logs.

## Disk sanitization

Before partitioning, the toolkit captures an immutable pre-operation identity
record:

- model, serial, WWN, capacity, sector size, transport, and kernel device
- existing partition, filesystem, and encryption identifiers
- detected media capabilities

It selects and records one of:

- ATA secure erase or sanitize for supported SATA devices
- NVMe format/sanitize for supported NVMe devices
- controlled overwrite for media where that is the best available method
- refusal when the media cannot provide an auditable or appropriate method

The command requires explicit target confirmation and writes `planned`,
`started`, and `completed` audit events. A failed or interrupted operation is
recorded as such and never represented as a successful wipe.

## Initramfs SSH unlock

The host receives a public key whose corresponding private key remains on the
vault-backed recovery controller. The initramfs `authorized_keys` entry uses a
forced command equivalent to `cryptroot-unlock` and disables:

- interactive shell access
- PTY allocation
- TCP forwarding
- agent forwarding
- X11 forwarding

Dropbear listens on the configured wired recovery address and port `2222`.
The regular Ubuntu SSH service is configured separately and is not used as the
initramfs unlock path.

The vault stores the unlock-key fingerprint, public key, creation time, target
machine identity, and initramfs deployment checksum. It never stores an
unrestricted private key in the host provisioning output.

## Vault-backed audit gate

Destructive disk and provisioning commands call a shared gate before changing
external media. The gate verifies:

1. The configured vault UUID is mounted at the expected path.
2. The recovery-toolkit vault directory is writable by the invoking user.
3. The target identity can be read and serialized.
4. A pre-operation audit record can be created and reopened.
5. No target identity conflicts with the requested operation.

The command records the result, exit status, timestamps, and checksums after
the operation. Secrets are excluded from human-readable logs; key material is
referenced by stable IDs and hashes.

## Ubuntu Server installer handoff

The recovery USB is already running the Ubuntu Server environment that will be
installed on the host. The host installer command uses Subiquity's documented
`--autoinstall <path>` entry point from that running environment, so the normal
Ubuntu Server image and installer backend remain responsible for populating the
target. The toolkit does not copy the live USB root filesystem and does not
rebuild the USB.

The generated autoinstall file is written only to the mounted vault with mode
`0600`. It contains the stable target path, the preserved GPT partition/LUKS2/
LVM/XFS storage graph, the vault path of the LUKS key file, and the operator's
host identity settings. The LUKS key contents are never inserted into YAML or
logs. Subiquity and its Curtin backend format the EFI and `/boot` partitions,
reuse the pre-created encrypted root graph, and populate the target from the
currently mounted installer source (normally `/cdrom`).

`install-ubuntu-server` is read-only by default. The mutating path requires the
vault audit gate, a stable target identity re-read, an exact fingerprint
confirmation, and an explicit `--apply`. It records the rendered config hash,
installer source identity, target fingerprint, and Subiquity exit status in the
vault. It never invokes a reboot and never writes to the recovery USB's boot
configuration.

## Evidence record

Each host gets a vault directory such as:

```text
/mnt/Vault/recovery-toolkit-vault/hosts/<host-id>/
  machine.json
  network-profile.env
  disk-history/<operation-id>.json
  luks/luks-header-<luks-uuid>.img
  luks/luks-header-<luks-uuid>.sha256
  keys/<key-id>.enc
  ssh/initramfs-unlock.pub
  ssh/initramfs-unlock.fingerprint
  manifests/provisioning-<operation-id>.json
```

Private key and LUKS-key files must use restrictive permissions and should be
encrypted at rest in the vault where the workflow supports it. The manifest
links the disk identity to every generated identifier without duplicating
secret contents into metadata.

## Implementation slices

1. Add host/recovery profile validation and a stable machine identity record.
2. Add vault-backed audit primitives and fail-closed integration into secure
   erase commands.
3. Add disk discovery, sanitization selection, and pre/post evidence records.
4. Add LUKS2/LVM/XFS provisioning with protected key generation and header
   backup.
5. Add the Subiquity/autoinstall host installation handoff.
6. Add Dropbear/initramfs configuration and restricted unlock-key deployment
   against the installed host root.
7. Build an end-to-end `slinky` test with a non-production target disk.
8. Revisit and harden the overlay boot mode only after recovery succeeds.

## Verification requirements

- Unit/fixture tests cover profile validation, audit refusal, identity
  serialization, key-file permissions, and forced-command generation.
- Shellcheck and repository tests pass.
- A live test proves the vault gate refuses when the vault is absent.
- A live test proves the gate records a harmless read-only target inspection.
- A live test proves Dropbear is bound to the expected address and port and
  rejects an unrestricted SSH command.
- A live test proves the unlock controller can unlock the test host.
- Header-backup checksum and a restore-to-test-container check pass before the
  USB is snapshotted.
