# LUKS Layout

## Storage Roles

Keep the bootable recovery OS USB disposable and write-light. It contains the
toolkit and temporary working state, but should not be the only place holding
operational secrets.

Use the separate hardware-encrypted USB as the persistent vault for:

- LUKS headers and recovery keys
- Recovery audit exports that must survive reboot
- Other sensitive recovery state

Do not add the vault USB to `/etc/fstab` for automatic mounting. Identify it
by stable vendor/serial information, mount it only for an intentional key
ceremony or backup operation, and unmount it immediately afterward. Verify the
device identity before every mount; never infer the target from `/dev/sdX`.

The hardware encryption protects the device at rest, but does not remove the
need for access control, independent backups, or careful handling while the
device is unlocked. If its hardware-encryption trust model is uncertain, add a
separate LUKS container inside it rather than storing cleartext keys directly.

## Existing Planning Notes
This toolkit will provide the ability to setup custom luks layouts. Some will be general patterns for all machines and others will be unique aspects for specific machines, such as specific cypthers for machines that cant handle standard encryption (MacMini 4,1).

Since a lot of disks start unencrypted, we should perform a secure erase within reason based
on the disk type we are targeting to install a ubuntu server node to.

We are going to use xfs since its ideal for docker and database environments

Lean towards generated keys with good entropy. Generate them only during an
intentional maintenance or key-ceremony session, write them to the separate
encrypted vault, and keep the OS USB free of long-lived cleartext key material.

link to 
[Hdd Secure Erase](./hdd-secure-erase.md)
[SSD Secure Erase](./ssd-secure-erase.md)
[nvme Secure Erase](./nvme-secure-erase.md)
