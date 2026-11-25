# SoraOS architecture

## The layer model

```
┌──────────────────────────────────────────────────────────────┐
│ SoraOS                                                       │
│   branding · defaults · SoraAgent · SoraDesk · installer     │
│   [soraos] packages · hosted signed mirror                   │
├──────────────────────────────────────────────────────────────┤
│ Arch Linux                                                   │
│   official repos · pacman · systemd · linux-lts · KDE Plasma │
├──────────────────────────────────────────────────────────────┤
│ archiso                                                      │
│   profile → live ISO build tool (not a runtime base)         │
└──────────────────────────────────────────────────────────────┘
```

archiso produces the live medium. The installed system is produced by
Calamares from packages, not by copying the live squashfs. Both consume the
same repositories, so a `pacman -Syu` on an installed SoraOS machine is the
same operation as on Arch, plus the SoraOS packages.

## Update model

- Official Arch mirrors are the source of truth for the base system.
- `[soraos]` is an additional repository, ordered after `[core]` and `[extra]`.
  It contains only SoraOS packages and the SoraPlatform products.
- No `IgnorePkg`, no pinned kernel, no partial upgrades.
- `pacman -Syu` remains the only supported full-update path. A future
  "curated snapshot" option, if ever added, must move **all** repositories to a
  dated snapshot; it must not hold back individual packages.
- The live system tries the hosted HTTPS mirror first and falls back to the
  signed repository carried on the live medium.
- Application self-updaters are not part of the model. SoraDesk is rebuilt and
  shipped through `[soraos]`; the package manager owns the installed binary.

## Repository and package flow

```
packages/<name>/PKGBUILD
        │
        ▼
scripts/build-repo.sh
        │  makepkg --nodeps --cleanbuild --clean
        ▼
repo/x86_64/<name>-<version>-<arch>.pkg.tar.zst
        │  gpg --detach-sign
        ▼
repo/x86_64/soraos.db.tar.gz  ←  repo-add --sign
        │  gpg --verify (both databases and every package)
        ├──────────────────────────────┐
        │                              │
        ▼                              ▼
staged into the ISO profile     scripts/publish-mirror.sh
airootfs/opt/soraos/repo        dereferenced static mirror
                                SoraOfficialWebsite/repo/x86_64
```

`scripts/build.sh` runs the repository build automatically, stages a copy
inside the profile, and removes the staged copy on exit. The staged repository
and `repo/` (which also holds the private test key) are not tracked by git.

The build host does not trust the local test key, so the build-only pacman
configuration uses `SigLevel = Never` for `[soraos]`. `build-repo.sh` verifies
the detached signatures separately before the ISO build starts. The live
system trusts `soraos-keyring` and uses `SigLevel = Required DatabaseOptional`.

The hosted mirror is the website's GitHub Pages directory:

```
Server = https://mochi-sora.github.io/SoraOfficialWebsite/repo/$arch
Server = file:///opt/soraos/repo/$arch
```

GitHub Pages does not follow symlinks, so `publish-mirror.sh` publishes
dereferenced `soraos.db` and `soraos.files` files and verifies every signature
again after copying. This is a development host and test key; see
[secureboot.md](secureboot.md) for why repository signing and boot signing are
different, and `README.md` for the production-key gate.

## Package ownership

| Package | Milestone | Purpose |
|---|---|---|
| `soraos-keyring` | M2a | Public signing key for `[soraos]`, populated by `pacman-key` |
| `soraos-mirrorlist` | M2a | Hosted and on-medium `[soraos]` server list |
| `soraos-release` | M2a | `/etc/os-release`, `/etc/issue`, `/etc/lsb-release`, release helpers and hooks |
| `soraos-branding` | M2a | Wallpapers, look-and-feel, color scheme, icons, MOTD, and skel defaults |
| `soraos-desktop-meta` | M2a | Plasma, KDE applications, products, networking, audio, and graphics dependencies |
| `sora-agent` | M2b | SoraAgent runtime, `sora`, `sora-gateway`, and `sora-memory` |
| `sora-desk` | M2b | Native Tauri SoraDesk client, built against Arch WebKitGTK |
| `sora-desk-bridge` | M2b | `sora-desktop` WebSocket bridge between SoraDesk and SoraAgent |
| `python-questionary` | M2b | Interactive prompts for `sora setup`; absent from `[extra]` |
| `soraos-installer` | M3 | Calamares configuration and branding |

The airootfs overlay contains only files that are genuinely live-only: Plasma
Login Manager configuration, the live user setup hook, pacman-init, the
accessibility units, and boot-related files. Anything that should exist on an
installed system comes from a package.

### Package scriptlets in the live build

`mkarchiso` uses `pacstrap -N`, so package `.install` scriptlets do not run
while the live image is assembled. `soraos-release` therefore exposes
`/usr/lib/soraos/write-release` and `/usr/lib/soraos/add-repo`; the one-shot
live setup hook calls both explicitly. Installed systems get the same helpers
from `soraos-release.install` on install and upgrade.

Permanent libalpm hooks live in `/usr/share/libalpm/hooks/`, not
`/etc/pacman.d/hooks/`, because archiso deletes build-only hooks from
`/etc/pacman.d/hooks/` after the package transaction.

## Product integration

### SoraAgent

`sora-agent` is built from the upstream release tag into the system Python
environment. Arch supplies `python-openai`, `python-typer`, `python-rich`,
`python-pypdf`, and `python-questionary`. The package provides the `sora`,
`sora-gateway`, and `sora-memory` commands and stores user state under
`~/.sora_agent`, as upstream expects.

### SoraDesk bridge

`sora-desk-bridge` installs the `sora-desktop` command from the
`SoraDesk/bridge` project and depends on `sora-agent` plus Arch's
`python-websockets`. Upstream pins `websockets>=15,<17`; the bridge smoke suite
passes on Arch's 17.2, so the package widens that guard to `<18` instead of
carrying a second websockets tree.

The bridge is a thin adapter, not a second agent: it builds SoraAgent's provider,
tools, memory, identity, calendar, sessions, and `ChatHandler`, then exposes the
frozen desktop protocol over loopback. SoraDesk finds it through `PATH` after
the package installs it in `/usr/bin`.

### SoraDesk

`sora-desk` is built from the upstream Tauri source, not repackaged from a
Debian or AppImage release. This keeps the binary linked against the current
Arch WebKitGTK, GLib, and ICU ABIs. The build uses the Tauri CLI
(`tauri build --no-bundle`), which is required to embed the production
`frontendDist`; a bare `cargo build --release` uses the dev-server URL.

The package installs the binary, desktop entry, icons, and license. Its check
phase runs the 69-check client protocol smoke suite before packaging. SoraDesk
can connect to a local bridge, an SSH tunnel, or an opt-in direct-IP endpoint;
the live image's default local path is SoraDesk → `sora-desktop` →
SoraAgent.

## Linux-lts wiring

`packages.x86_64` installs `linux-lts` instead of `linux`. archiso copies every
installed `vmlinuz-*` and `initramfs-*.img` into the ISO, and the boot entries
reference the LTS names:

```
/%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux-lts
/%INSTALL_DIR%/boot/%ARCH%/initramfs-linux-lts.img
```

`mkinitcpio-archiso` and the `archiso` hook in
`airootfs/etc/mkinitcpio.conf.d/archiso.conf` are preserved. No kernel source,
config, or patch set is involved.

The `linux` (latest) package stays available in the official repos as a
post-install fallback for hardware that LTS does not support yet. It is not on
the ISO.

## Live session

- `soraos-airootfs-setup` runs once at the end of the ISO package transaction
  from `90-soraos-setup.hook`. It applies the package-owned release/repository
  helpers, creates the `sora` user, configures passwordless sudo, enables
  services, and removes itself and its hook.
- Plasma Login Manager (`plasmalogin`) autologins `sora`; its greeter wallpaper
  is set in `/etc/plasmalogin.conf` and supplied by `soraos-branding`.
- `pacman-init.service` initializes the pacman keyring on a tmpfs and populates
  both `archlinux` and `soraos`.
- The Arch mirrorlist hook has already uncommented HTTPS mirrors at build time.
- The live `[soraos]` repository is at `/opt/soraos/repo/$arch`; the hosted
  HTTPS mirror is the first `Server` entry.
- The live CoW space is raised to 4 GiB with `cow_spacesize=4G`.

## Build path

```
make check   static validation (packages, kernel names, repository, branding)
make repo    makepkg → detached signatures → repo-add → signature verification
make iso     build-repo.sh (unless SORAOS_SKIP_REPO=1)
             └─ stage repo → mkarchiso 92 → squashfs → xorriso
make publish verify → dereference → copy into the static mirror checkout
make run     QEMU UEFI (run_archiso when available, plain QEMU otherwise)
```

archiso 92 supports unprivileged builds through
`unshare --map-auto --map-root-user`. The build script verifies this and falls
back to a privileged container only when requested.

Two build details matter for repeatability:

- `mkarchiso` is run with stdin from `/dev/null` so pacman cannot block on an
  interactive provider prompt.
- Cached copies of locally rebuilt packages and stale unshare-owned work
  directories are removed before a build. Rebuilding a package with the same
  filename must not leave pacman with an old checksum.

SoraDesk adds Rust, Node.js, npm, WebKitGTK, and GTK 3 to the build host
requirements. npm and Cargo need network access on a cold build.

## Installation path (M3)

Calamares will install from packages through the same repository definition,
not by copying the live squashfs. The hosted signed mirror from M2b is the
durable package source for an installed system; the `file://` repository on the
live medium is not a valid update source after installation.

## Secure Boot

The live ISO is unsigned, so Secure Boot must be disabled until the signing
pipeline in [secureboot.md](secureboot.md) lands. The `[soraos]` package
signatures do not change that. The Secure Boot chain is M4 and is optional; if
it is descoped, the documented requirement remains "Secure Boot off".
