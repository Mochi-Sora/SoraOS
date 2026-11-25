# Testing the SoraOS live image

## What the build produces

```
out/soraos-YYYY.MM.DD-x86_64.iso
out/soraos-YYYY.MM.DD-x86_64.iso.sha256
```

`make check` must pass before a build is considered valid. It resolves every
package against the sync databases, verifies the LTS kernel names in both boot
loaders, and confirms the build-time and live `pacman.conf` have not drifted.

## Boot matrix

| Firmware | Command | Expected |
|---|---|---|
| UEFI | `make run` | systemd-boot menu, then Plasma greeter autologins `sora` |
| BIOS | `make run-bios` | syslinux menu, then Plasma greeter autologins `sora` |
| UEFI + Secure Boot | `make run-sb` | **expected to be rejected** until the signing pipeline lands |

`make run` uses `run_archiso` when available and otherwise falls back to a
plain QEMU invocation. For a manual run:

```bash
qemu-system-x86_64 -machine q35 -m 4096 -smp 4 -enable-kvm -cpu host \
  -device virtio-vga -device qemu-xhci -device usb-tablet \
  -nic user,model=virtio-net-pci \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
  -cdrom out/soraos-*.iso
```

## Live-session checklist

Run these inside the live desktop unless noted otherwise.

### Boot and identity

- [ ] Firmware menu shows **SoraOS Live** with the SoraOS splash on BIOS.
- [ ] systemd-boot menu appears within 5 seconds and boots the LTS entry.
- [ ] No `systemd-firstboot` prompt appears; boot reaches the greeter directly.
- [ ] Plymouth is not configured; boot messages are acceptable for M1.
- [ ] `cat /etc/os-release` shows `ID=soraos`, `ID_LIKE=arch`.
- [ ] `hostnamectl` reports `soraos`.
- [ ] `uname -r` ends in `-lts`.

### Session

- [ ] Plasma Login Manager autologins `sora` without a password.
- [ ] The greeter and desktop use the SoraOS dark wallpaper.
- [ ] Look and feel is **SoraOS** (`plasma-apply-lookandfeel --list`).
- [ ] `id sora` shows `wheel,video,render,audio,optical,storage`.
- [ ] `sudo -n true` succeeds (passwordless sudo in the live session).
- [ ] Dolphin, Konsole, Kate, Ark, Gwenview, Okular and Firefox launch.
- [ ] Wayland session is active (`echo $XDG_SESSION_TYPE`), X11 fallback works.

### System services

- [ ] NetworkManager is running and the Ethernet interface gets DHCP.
- [ ] `ping -c1 archlinux.org` succeeds after DHCP.
- [ ] Wi-Fi networks are listed in the Plasma applet (if hardware exists).
- [ ] Bluetooth adapter is powered and discoverable (if hardware exists).
- [ ] `wpctl status` shows PipeWire and WirePlumber running.
- [ ] Audio plays through the default sink (test with `speaker-test`).
- [ ] `timedatectl` shows NTP synchronized once the network is up.
- [ ] `systemctl is-system-running` reports `running` or `degraded` only for
      expected missing hardware units.

### Live-medium behavior

- [ ] `findmnt /` shows the squashfs + overlay, not a physical disk.
- [ ] Writing a file to `$HOME` works (CoW space is 4 GiB).
- [ ] `pacman -Sy` works without a keyring error (pacman-init ran).
- [ ] `journalctl --no-pager -b -p err` has no SoraOS-induced errors.
- [ ] In QEMU, a failed `systemd-loop@...-sr0.service` is expected: systemd-dissect
      scans the emulated CD-ROM and finds no partitions.
- [ ] Rebooting returns to a clean live session (no stored users or files).

### Accessibility entry

- [ ] The "with speech" entry boots with `accessibility=on`.
- [ ] `systemctl status livecd-talk.service` reports success.
- [ ] `systemctl status espeakup.service` is active and speech is audible.

For a complete QEMU test, give the guest a sound card so espeakup has a sink:
`-audiodev none,id=snd0 -device intel-hda -device hda-duplex,audiodev=snd0`.
Without any audio hardware the speech units are expected to fail.

## Release checks

- [ ] `sha256sum -c out/*.iso.sha256` passes.
- [ ] ISO label is `SORAOS_YYYYMM` (`xorriso -indev out/*.iso -pvd_info | grep -i 'Volume id'`).
- [ ] The ISO boots in QEMU with 2 GiB RAM.
- [ ] The ISO boots on real UEFI hardware with Secure Boot **disabled**.
- [ ] Known limitations in `README.md` are still accurate.

## Failure triage

| Symptom | Likely cause |
|---|---|
| `mount: /run/archiso/bootmnt: special device does not exist` | initramfs lacks the `archiso` hook; check `iso/airootfs/etc/mkinitcpio.conf.d/archiso.conf` |
| Kernel panic finding root | boot entry points at `vmlinuz-linux` instead of `vmlinuz-linux-lts` |
| Black screen after boot | GPU driver missing; try the X11 session or `nomodeset` |
| Greeter asks for a password | `/etc/plasmalogin.conf` missing or wrong `User=`/`Session=` |
| Boot hangs at an **Initial Setup** prompt | `systemd-firstboot` ran because `/etc/machine-id` is `uninitialized`; check `systemd.firstboot=no` in `profiledef.sh` and the mask symlink in `airootfs` |
| Speech entry: `Unable to locate executable '/usr/local/bin/livecd-sound': Permission denied` | `mkarchiso` does not preserve modes; list the script as `0:0:755` in `file_permissions` |
| Speech entry: `livecd-talk` fails but the desktop is fine | QEMU without a sound card; add `-device intel-hda -device hda-duplex` or retest on hardware |
| No network | NetworkManager unit not enabled or firmware package missing |
| Secure Boot rejects the ISO | expected; the M1 image is unsigned |
