# ssd-secure-erase

Before running this destructive command, configure and unlock the separate
vault with `make usb-vault`. The command fails closed unless it can capture the
target identity and write a `planned` audit record to the UUID-bound vault.
Completion or failure, including the utility exit status, is recorded after
the operation. Plaintext keys and secrets are never written to the record.

Securely erases a SATA SSD (or other flash-based disk that isn't NVMe) before
it is repurposed or decommissioned.

```
sudo ssd-secure-erase /dev/sdX
```

## Behavior
1. Refuses to run against the active root or vault disk (`assert_not_protected_disk`).
2. Warns if the target reports as rotational (use
   [hdd-secure-erase](./hdd-secure-erase.md) instead).
3. Prompts for explicit confirmation (`NUKE`) before touching the disk.
4. Attempts, in order:
   - ATA secure erase (`hdparm --security-erase`)
   - TRIM-based secure discard (`blkdiscard --secure`)
   - Fallback single-pass overwrite (`shred -n 1`)

For NVMe devices, use [nvme-secure-erase](./nvme-secure-erase.md) instead,
which uses the NVMe sanitize/format command set.
