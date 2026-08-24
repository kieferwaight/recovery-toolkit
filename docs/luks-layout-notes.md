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

`provision-luks` currently provides a read-only plan by default. It requires a
stable target identity and refuses the active recovery USB. The mutating path
will remain behind the vault audit gate and explicit identity confirmation.

Use the following sequence during a host provisioning or recovery session:

```bash
sudo make usb-preflight
sudo make usb-vault
sudo inspect-disk /dev/disk/by-id/<target>
sudo hdd-secure-erase --target /dev/disk/by-id/<target>   # select the media-appropriate erase command
sudo provision-luks --target /dev/disk/by-id/<target>
sudo install-ubuntu-server --target /dev/disk/by-id/<target>
sudo install-ubuntu-server --target /dev/disk/by-id/<target> --apply
sudo mount <installed-host-root> /mnt/host
sudo setup-initramfs-unlock --target-root /mnt/host
sudo setup-initramfs-unlock --target-root /mnt/host --apply
```

If you are only maintaining the recovery USB itself, do not run the host
provisioning commands. USB maintenance work stays separate and should not
require rebooting the installer environment just to continue host deployment.
Use `make usb-*` only for deliberate changes to the recovery USB.

Review the fingerprint and planned commands first. Mutating host operations
require the vault to be mounted, the target fingerprint to be re-read and
confirmed, and the explicit `NUKE` confirmation where disk destruction is
involved. Never use `/dev/sdX` as the
operator-facing target identifier.

`install-ubuntu-server --apply` starts the official Ubuntu Server Subiquity
installer from the currently booted environment and points it at the
vault-rendered autoinstall configuration. The configuration preserves the
prepared encrypted root graph, formats only EFI and `/boot`, and uses the
installer source already mounted at `/cdrom`. It does not modify the recovery
USB. `setup-initramfs-unlock` is a host-facing command and requires the
installed host root to be mounted explicitly with `--target-root`; it writes
Dropbear files below that root and runs the rebuild through `chroot`.

link to 
[Hdd Secure Erase](./hdd-secure-erase.md)
[SSD Secure Erase](./ssd-secure-erase.md)
[nvme Secure Erase](./nvme-secure-erase.md)
