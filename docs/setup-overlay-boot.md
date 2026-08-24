# setup-overlay-boot

This is a recovery USB maintenance command, not part of the host provisioning
workflow. Keep it out of the live host path unless you intentionally need to
rebuild the USB boot behavior.

Configures the recovery USB with three selectable GRUB boot profiles so the
USB can be dropped into ephemeral "provisioning" use without risking wear or
data leakage, while still allowing a persistent mode for maintenance.

```
sudo make usb-overlay
```

Direct execution of the script under `scripts/usb/` is rejected; the Makefile
preflight prints the active USB root and vault identities first.

## Behavior
1. Installs `overlayroot` and configures it to use a tmpfs overlay
   (`overlayroot.conf`).
2. Determines the root filesystem UUID and writes a custom
   `/etc/grub.d/40_custom` with three menu entries:
   - **Ephemeral RAM Mode (default)** — root mounted read-only, all writes
     land in a RAM-backed overlay that is discarded on reboot. This is the
     safe default for day-to-day recovery/provisioning work.
   - **Persistent Maintenance Mode** — root mounted read-write with the
     overlay disabled, for applying updates or managing the LUKS key vault.
   - **Airgapped Key Ceremony** — RAM overlay plus network interfaces
     blacklisted at the kernel level, for generating/handling LUKS keys
     without any network exposure.
3. Updates `/etc/default/grub` (default entry + timeout) and regenerates
   `initramfs`/GRUB.

## Notes
- Re-run after kernel upgrades to keep `update-initramfs`/`update-grub` in
  sync.
- Pair with [luks-layout-notes.md](./luks-layout-notes.md) when deciding
  which mode to boot into for key management tasks.
