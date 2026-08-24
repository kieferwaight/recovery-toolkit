# hdd-secure-erase

Before running this destructive command, configure and unlock the separate
vault with `make usb-vault`. The command fails closed unless it can capture the
target identity and write a `planned` audit record to the UUID-bound vault.
Completion or failure, including the utility exit status, is recorded after
the operation. Plaintext keys and secrets are never written to the record.

Securely erases a rotational (spinning) hard disk before it is repurposed or
decommissioned.

```
sudo hdd-secure-erase /dev/sdX
```

## Behavior
1. Refuses to run against the active root or vault disk (`assert_not_protected_disk`).
2. Warns if the target does not report as rotational (use
   [ssd-secure-erase](./ssd-secure-erase.md) instead).
3. Prompts for explicit confirmation (`NUKE`) before touching the disk.
4. Attempts, in order:
   - ATA **enhanced** secure erase (`hdparm --security-erase-enhanced`)
   - Standard ATA secure erase (`hdparm --security-erase`)
   - Fallback single-pass overwrite (`shred -n 1`) if the drive doesn't
     report ATA secure erase support.

## Notes
- Some drives lock up if the host goes to sleep mid-erase; keep the USB
  session active (`make usb-overlay` maintenance mode) until it completes.
- See [luks-layout-notes.md](./luks-layout-notes.md) for what happens after
  the disk is wiped (LUKS layout, key storage).
