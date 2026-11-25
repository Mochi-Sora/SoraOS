# Testing SoraOS

## What the build produces

```
repo/x86_64/*.pkg.tar.zst
repo/x86_64/*.pkg.tar.zst.sig
repo/x86_64/soraos.db.tar.gz
repo/x86_64/soraos.db.tar.gz.sig
out/soraos-YYYY.MM.DD-x86_64.iso
out/soraos-YYYY.MM.DD-x86_64.iso.sha256
```

`make check` must pass before a build is considered valid. It resolves every
package (including the local `soraos-*` sources), verifies the LTS kernel names
in both boot loaders, checks the live setup wiring, and confirms the installed
branding matches the sources. It does not replace `build-repo.sh`'s signature
verification.

## Repository checks

Run these on the build host before booting anything:

```bash
./scripts/gen-test-key.sh   # only if repo/keys/keyid does not exist yet
make repo
```

Expected:

- `repo/x86_64` contains five packages, `soraos.db.tar.gz`, `soraos.files.tar.gz`,
  and a detached `.sig` for each package and database.
- `build-repo.sh` ends with all `gpg --verify` calls succeeding.
- `repo/keys/` and `repo/x86_64/` do not appear in `git status`; only the public
  keyring under `packages/soraos-keyring/files/` is committed.

Verify independently with the repository keyring:

```bash
GNUPGHOME=repo/keys/gnupg gpg --verify \
  repo/x86_64/soraos.db.tar.gz.sig repo/x86_64/soraos.db.tar.gz
GNUPGHOME=repo/keys/gnupg gpg --verify \
  repo/x86_64/soraos.files.tar.gz.sig repo/x86_64/soraos.files.tar.gz
for sig in repo/x86_64/*.pkg.tar.zst.sig; do
  GNUPGHOME=repo/keys/gnupg gpg --verify "$sig" "${sig%.sig}"
done
```

After `make iso`, confirm the staged copy was removed from the working tree:

```bash
test ! -e iso/airootfs/opt/soraos/repo
```

The repository is still inside the ISO because it was staged while `mkarchiso`
copied the airootfs.

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
- [ ] Plymouth is not configured; boot messages are acceptable for M2a.
- [ ] `cat /etc/os-release` shows `ID=soraos`, `ID_LIKE=arch`.
- [ ] `hostnamectl` reports `soraos`.
- [ ] `uname -r` ends in `-lts`.
- [ ] `pacman -Q soraos-keyring soraos-mirrorlist soraos-release soraos-branding soraos-desktop-meta`
      lists all five packages.

### Signed [soraos] repository

- [ ] `pacman-key --list-keys` includes the **SoraOS Test Repository** key.
- [ ] `pacman -Sl soraos` lists all five `soraos-*` packages.
- [ ] `sudo pacman -Sy` exits 0 without a keyring or signature error.
- [ ] `/etc/pacman.conf` contains `[soraos]` with
      `SigLevel = Required DatabaseOptional` and
      `Include = /etc/pacman.d/soraos-mirrorlist`.
- [ ] `pacman -Qi soraos-release` reports the `soraos` repository.
- [ ] `pacman -Qkk soraos-branding` reports no altered files.
- [ ] `pacman -Qo /usr/share/wallpapers/SoraOS/metadata.json` and
      `pacman -Qo /etc/skel/.config/kdeglobals` both report `soraos-branding`.
- [ ] `pacman -Qo /usr/share/soraos/os-release` reports `soraos-release`,
      and `/usr/lib/os-release` carries the SoraOS identity written by its helper.
- [ ] Reinstalling a signed package verifies against the live keyring:
      `sudo pacman -U /opt/soraos/repo/x86_64/soraos-mirrorlist-*.pkg.tar.zst`.

The `file:///opt/soraos/repo/x86_64` source is expected in M2a. A hosted mirror
arrives in M2b.

### Session

- [ ] Plasma Login Manager autologins `sora` without a password.
- [ ] The greeter and desktop use the SoraOS dark wallpaper.
- [ ] The SoraOS mark is the gradient **S**, not the website placeholder **H**;
      accents are blue/purple (`#7aa2f7` / `#bb9af7`).
- [ ] Look and feel is **SoraOS** (`plasma-apply-lookandfeel --list`).
- [ ] Color scheme is **SoraOS** (`plasma-apply-colorscheme --list`).
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

- [ ] `make check` and `make repo` pass, including every signature verification.
- [ ] `sha256sum -c out/*.iso.sha256` passes.
- [ ] ISO label is `SORAOS_YYYYMM` (`xorriso -indev out/*.iso -pvd_info | grep -i 'Volume id'`).
- [ ] The ISO boots in QEMU with 2 GiB RAM.
- [ ] The ISO boots on real UEFI hardware with Secure Boot **disabled**.
- [ ] The live session can complete `sudo pacman -Sy` and `pacman -Sl soraos`.
- [ ] Known limitations in `README.md` are still accurate.
- [ ] **Do not call this a public release**: the repo key is a test key and the
      mirror is `file:///opt/soraos/repo/$arch`.

## Failure triage

| Symptom | Likely cause |
|---|---|
| `mount: /run/archiso/bootmnt: special device does not exist` | initramfs lacks the `archiso` hook; check `iso/airootfs/etc/mkinitcpio.conf.d/archiso.conf` |
| Kernel panic finding root | boot entry points at `vmlinuz-linux` instead of `vmlinuz-linux-lts` |
| Black screen after boot | GPU driver missing; try the X11 session or `nomodeset` |
| Greeter asks for a password | `/etc/plasmalogin.conf` missing or wrong `User=`/`Session=` |
| Pink **H** logo or Breeze Dark colors | stale branding assets; run `make branding`, confirm `ColorScheme=SoraOS`, and rebuild |
| Boot hangs at an **Initial Setup** prompt | `systemd-firstboot` ran because `/etc/machine-id` is `uninitialized`; check `systemd.firstboot=no` in `profiledef.sh` and the mask symlink in `airootfs` |
| Speech entry: `Unable to locate executable '/usr/local/bin/livecd-sound': Permission denied` | `mkarchiso` does not preserve modes; list the script as `0:0:755` in `file_permissions` |
| Speech entry: `livecd-talk` fails but the desktop is fine | QEMU without a sound card; add `-device intel-hda -device hda-duplex` or retest on hardware |
| No network | NetworkManager unit not enabled or firmware package missing |
| `make repo` says `no signing key` | run `./scripts/gen-test-key.sh` or set `SORAOS_GNUPGHOME` |
| Build fails with `key ... is unknown` | the build-only pacman config did not add `[soraos]`, or a stale `iso/pacman.conf` was used; check `scripts/build.sh` |
| Build fails with `target not found: soraos-*` | `repo/x86_64` is missing or the staged repository was not copied; run `make repo` and retry |
| Live `pacman -Sy` says a key is unknown | `pacman-init.service` failed or `soraos-keyring` is absent; run `sudo pacman-key --populate soraos` and inspect the unit |
| `pacman -U` reports an invalid signature | repository and ISO were built with different keys, or the live keyring is stale; rebuild the repo and ISO |
| A `soraos-*` package is missing from `pacman -Sl soraos` | the staged repository is incomplete; rerun `make repo` and rebuild the ISO |
| Secure Boot rejects the ISO | expected; the live image is unsigned, and package signing does not sign the boot chain |
