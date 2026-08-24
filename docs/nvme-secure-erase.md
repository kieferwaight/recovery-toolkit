# nvme-secure-erase

Before running this destructive command, configure and unlock the separate
vault with `make usb-vault`. The command fails closed unless it can capture the
target identity and write a `planned` audit record to the UUID-bound vault.
Completion or failure, including the utility exit status, is recorded after
the operation. Plaintext keys and secrets are never written to the record.

Securely erases an NVMe disk before it is repurposed or decommissioned.

```
sudo nvme-secure-erase /dev/nvmeXn1
```

## Behavior
1. Refuses to run against the active root or vault disk (`assert_not_protected_disk`).
2. Reports whether the controller supports sanitize.
3. Prompts for explicit confirmation (`NUKE`) before touching the disk.
4. Issues a crypto-scramble format (`nvme format --ses=1`) against namespace 1.

For SATA SSDs/HDDs, use [ssd-secure-erase](./ssd-secure-erase.md) or
[hdd-secure-erase](./hdd-secure-erase.md) instead.
