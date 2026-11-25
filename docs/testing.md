# Testing SoraOS

## What the build produces

```
repo/x86_64/*.pkg.tar.zst
repo/x86_64/*.pkg.tar.zst.sig
repo/x86_64/soraos.db
repo/x86_64/soraos.db.sig
repo/x86_64/soraos.files
repo/x86_64/soraos.files.sig
out/soraos-YYYY.MM.DD-x86_64.iso
out/soraos-YYYY.MM.DD-x86_64.iso.sha256
```

`make check` must pass before a build is considered valid. It resolves every
package (including the local source packages), verifies the LTS kernel names in
both boot loaders, checks the live setup wiring, and confirms the installed
branding matches the sources. It does not replace `build-repo.sh`'s signature
verification.

## Repository checks

Run these on the build host before booting anything:

```bash
./scripts/gen-test-key.sh   # only if repo/keys/keyid does not exist yet
make repo
```

Expected:

- `repo/x86_64` contains nine packages, `soraos.db`, `soraos.files`, and a
  detached `.sig` for each package and database.
- `build-repo.sh` ends with all `gpg --verify` calls succeeding.
- `repo/keys/` and `repo/x86_64/` do not appear in `git status`; only the public
  keyring under `packages/soraos-keyring/files/` is committed.
- SoraDesk's source build runs the 69-check protocol smoke suite before the
  package is created.

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

### Bridge dependency check

The bridge upstream pins `websockets<17`, while Arch ships 17.x. The package
widens the guard only after this check passes:

```bash
python -m venv /tmp/soradesk-bridge-test
/tmp/soradesk-bridge-test/bin/pip install --no-deps /path/to/SoraAgent
/tmp/soradesk-bridge-test/bin/pip install --no-deps /path/to/SoraDesk/bridge
/tmp/soradesk-bridge-test/bin/pip install 'websockets==17.2'
/tmp/soradesk-bridge-test/bin/python /path/to/SoraDesk/bridge/tests/smoke.py
```

Expect `smoke: all checks passed`. Re-run this after a SoraDesk bridge bump.

### Hosted mirror checks

```bash
make publish
curl -fsSI https://mochi-sora.github.io/SoraOfficialWebsite/repo/x86_64/soraos.db
```

The mirror path must be a regular file, not a symlink, and the `.sig` files must
verify with the committed keyring. GitHub Pages can take a minute to deploy a
new directory.

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
- [ ] Plymouth is not configured; boot messages are acceptable for M2b.
- [ ] `cat /etc/os-release` shows `ID=soraos`, `ID_LIKE=arch`.
- [ ] `hostnamectl` reports `soraos`.
- [ ] `uname -r` ends in `-lts`.
- [ ] `pacman -Q soraos-keyring soraos-mirrorlist soraos-release soraos-branding soraos-desktop-meta`
      lists all five base packages.
- [ ] `pacman -Q sora-agent sora-desk sora-desk-bridge python-questionary` lists
      the four M2b packages.

### Signed [soraos] repository and hosted mirror

- [ ] `pacman-key --list-keys` includes the **SoraOS Test Repository** key.
- [ ] `pacman -Sl soraos` lists all nine packages.
- [ ] `sudo pacman -Syy` exits 0 without a keyring or signature error.
- [ ] `/etc/pacman.conf` contains `[soraos]` with
      `SigLevel = Required DatabaseOptional` and
      `Include = /etc/pacman.d/soraos-mirrorlist`.
- [ ] `cat /etc/pacman.d/soraos-mirrorlist` shows the HTTPS mirror first and
      `file:///opt/soraos/repo/$arch` second.
- [ ] `curl -fsSI https://mochi-sora.github.io/SoraOfficialWebsite/repo/x86_64/soraos.db`
      returns `200`.
- [ ] `pacman -Qi soraos-release` reports the `soraos` repository.
- [ ] `pacman -Qkk soraos-branding` reports no altered files.
- [ ] `pacman -Qo /usr/share/wallpapers/SoraOS/metadata.json` and
      `pacman -Qo /etc/skel/.config/kdeglobals` both report `soraos-branding`.
- [ ] `pacman -Qo /usr/share/soraos/os-release` reports `soraos-release`, and
      `/usr/lib/os-release` carries the SoraOS identity written by its helper.
- [ ] Reinstalling a signed package verifies against the live keyring:
      `sudo pacman -U /opt/soraos/repo/x86_64/soraos-mirrorlist-*.pkg.tar.zst`.

### SoraAgent and the bridge

- [ ] `sora --version` prints `sora-agent 0.4.0`.
- [ ] `sora --help` starts without an import error.
- [ ] `sora-memory --help` and `sora-gateway --help` start without an import error.
- [ ] `sora-desktop --version` prints `sora-desktop 0.2.3`.
- [ ] `sora-desktop start` prints a `ws://127.0.0.1:18791` endpoint.
- [ ] `sora-desktop status` reports `running` with a pid, log, and devices count.
- [ ] `sora-desktop logs --tail 20 --no-follow` shows no traceback.
- [ ] `sora-desktop stop` stops it and removes `~/.sora_agent/run/desktop.json`.

### SoraDesk

- [ ] `soradesk` opens the dark SoraDesk window with Chat, Sessions, Calendar,
      Specialists, Memories, and Settings.
- [ ] The app is the packaged frontend, not a white "Could not connect to
      localhost: connection refused" webview error.
- [ ] Create a local profile in Settings (or write a local profile and restart).
- [ ] With the bridge running, the profile connects and the top bar shows
      **Connected · local**.
- [ ] The window can be closed and reopened without losing the profile.
- [ ] The in-app updater is not used on SoraOS; updates come from pacman.

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
- [ ] `make publish` succeeds and the hosted `.db` is a regular file.
- [ ] `sha256sum -c out/*.iso.sha256` passes.
- [ ] ISO label is `SORAOS_YYYYMM` (`xorriso -indev out/*.iso -pvd_info | grep -i 'Volume id'`).
- [ ] The ISO boots in QEMU with 2 GiB RAM.
- [ ] The ISO boots on real UEFI hardware with Secure Boot **disabled**.
- [ ] The live session can complete `sudo pacman -Syy`, `pacman -Sl soraos`, and
      launch SoraDesk connected to the local bridge.
- [ ] Known limitations in `README.md` are still accurate.
- [ ] **Do not call this a public release**: the repo key is a test key and the
      mirror is a GitHub Pages development host.

## Failure triage

| Symptom | Likely cause |
|---|---|
| ISO build stops at `Enter a number (default=1)` | a provider choice was not pinned; add the provider package and keep `mkarchiso` stdin on `/dev/null` |
| `cp: error writing '/tmp/pacman.conf...': No space left on device` | the host `/tmp` is full (often old ISO test images); clear it and retry |
| Build stops at package install with `target not found: soraos-*` | local repo staging failed or pacman used a stale build config; run `make repo` and retry |
| `corrupted (invalid or corrupted package (checksum))` for a local package | old cached package with the same filename; the build clears local cache entries, or remove `.cache/pacman/pkg/soraos-*` manually |
| `Permission denied` while removing `work/` | a failed userns build left root-owned files; `build.sh` retries through `unshare`, or run `unshare --map-auto --map-root-user rm -rf work` |
| `mount: /run/archiso/bootmnt: special device does not exist` | initramfs lacks the `archiso` hook; check `iso/airootfs/etc/mkinitcpio.conf.d/archiso.conf` |
| Kernel panic finding root | boot entry points at `vmlinuz-linux` instead of `vmlinuz-linux-lts` |
| Black screen after boot | GPU driver missing; try the X11 session or `nomodeset` |
| Greeter asks for a password | `/etc/plasmalogin.conf` missing or wrong `User=`/`Session=` |
| Pink **H** logo or Breeze Dark colors | stale branding assets; run `make branding`, confirm `ColorScheme=SoraOS`, and rebuild |
| Boot hangs at an **Initial Setup** prompt | `systemd-firstboot` ran because `/etc/machine-id` is `uninitialized`; check `systemd.firstboot=no` in `profiledef.sh` and the mask symlink in `airootfs` |
| SoraDesk shows **Could not connect to localhost** | binary built with a bare `cargo build`; rebuild with `tauri build --no-bundle` so `frontendDist` is embedded |
| SoraDesk window is black for a second | WebKit is still loading the bundled frontend; wait for the UI, then check `~/.config/com.mochi-sora.soradesk/` and the bridge |
| SoraDesk has no profile / Connect disabled | add a local profile in Settings, or ensure the bridge is running and the profile is active |
| `sora-desktop` not found by Settings | install `sora-desk-bridge`; the app searches `PATH`, `~/.local/bin`, `~/.sora_agent/venv/bin`, Homebrew, and `/usr/local/bin` |
| `make repo` says `cargo not found` | install `rust` and `npm`; SoraDesk is built from source |
| Bridge fails its smoke suite on `websockets` 17 | re-check the upstream guard and the bridge smoke output before widening the pin |
| Speech entry: `Unable to locate executable '/usr/local/bin/livecd-sound': Permission denied` | `mkarchiso` does not preserve modes; list the script as `0:0:755` in `file_permissions` |
| Speech entry: `livecd-talk` fails but the desktop is fine | QEMU without a sound card; add `-device intel-hda -device hda-duplex` or retest on hardware |
| No network | NetworkManager unit not enabled or firmware package missing |
| Secure Boot rejects the ISO | expected; the live image is unsigned, and package signing does not sign the boot chain |
