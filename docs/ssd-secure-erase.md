# ssd-secure-erase

Securely erases a SATA SSD (or other flash-based disk that isn't NVMe) before
it is repurposed or decommissioned.

```
sudo ssd-secure-erase /dev/sdX
```

## Behavior
1. Refuses to run against the active boot USB (`assert_not_boot_disk`).
2. Warns if the target reports as rotational (use
   [hdd-secure-erase](./hdd-secure-erase.md) instead).
3. Prompts for explicit confirmation (`NUKE`) before touching the disk.
4. Attempts, in order:
   - ATA secure erase (`hdparm --security-erase`)
   - TRIM-based secure discard (`blkdiscard --secure`)
   - Fallback single-pass overwrite (`shred -n 1`)

For NVMe devices, use [nvme-secure-erase](./nvme-secure-erase.md) instead,
which uses the NVMe sanitize/format command set.
