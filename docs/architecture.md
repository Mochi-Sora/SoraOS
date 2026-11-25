# SoraOS architecture

## The layer model

```
┌──────────────────────────────────────────────────────────────┐
│ SoraOS                                                       │
│   branding · defaults · soraos-* packages · installer        │
│   [soraos] repo · release engineering                        │
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

M2a is the first milestone where the product layer is real packages rather
than files copied into the airootfs overlay.

## Update model

- Official Arch mirrors are the source of truth for the base system.
- `[soraos]` is an additional repository, ordered after `[core]` and `[extra]`.
  It contains only SoraOS packages.
- No `IgnorePkg`, no pinned kernel, no partial upgrades.
- `pacman -Syu` remains the only supported full-update path. A future
  "curated snapshot" option, if ever added, must move **all** repositories to a
  dated snapshot; it must not hold back individual packages.
- M2a serves `[soraos]` from the live medium itself. M2b replaces that with a
  hosted mirror signed by an offline production key so installed systems can
  update normally.

## Package and repository flow

```
packages/<name>/PKGBUILD
        │
        ▼
scripts/build-repo.sh
        │  makepkg --nodeps --cleanbuild --clean
        ▼
repo/x86_64/<name>-<version>-any.pkg.tar.zst
        │  gpg --detach-sign
        ▼
repo/x86_64/soraos.db.tar.gz  ←  repo-add --sign
        │  gpg --verify (database and every package)
        ▼
┌───────────────────────────────┬───────────────────────────────┐
│ repo/x86_64 on the build host │ staged into the ISO profile   │
│ for reuse and inspection      │ airootfs/opt/soraos/repo      │
└───────────────────────────────┴───────────────────────────────┘
```

`scripts/build.sh` runs the repository build automatically, stages a copy
inside the profile, and removes the staged copy on exit. The staged repository
is not tracked by git, and neither is `repo/` (which also holds the private
test key).

The build host does not trust the local test key, so the build-only pacman
configuration uses `SigLevel = Never` for `[soraos]`. `build-repo.sh` verifies
the detached signatures separately before the ISO build starts. The live
system trusts `soraos-keyring` and uses `SigLevel = Required DatabaseOptional`.

That split matters: package signatures are a repository trust mechanism, not
Secure Boot. A signed package proves its origin to pacman; it does not make an
unsigned boot chain acceptable to firmware.

## Package ownership

| Package | Milestone | Purpose |
|---|---|---|
| `soraos-keyring` | M2a | Public signing key for `[soraos]`, populated by `pacman-key` |
| `soraos-mirrorlist` | M2a | `[soraos]` server list |
| `soraos-release` | M2a | `/etc/os-release`, `/etc/issue`, `/etc/lsb-release`, release helpers and hooks |
| `soraos-branding` | M2a | Wallpapers, look-and-feel, color scheme, icons, MOTD, and skel defaults |
| `soraos-desktop-meta` | M2a | Plasma, KDE applications, networking, audio, and graphics dependencies |
| SoraAgent/SoraDesk integration | M2b | Product packages and the hosted repository |
| `soraos-installer` | M3 | Calamares configuration and branding |

The airootfs overlay now contains only files that are genuinely live-only:
Plasma Login Manager configuration, the live user setup hook, pacman-init, the
accessibility units, and the boot-related files. Anything that should exist on
an installed system comes from a package.

### Package scriptlets in the live build

`mkarchiso` uses `pacstrap -N`, so package `.install` scriptlets do not run
while the live image is assembled. `soraos-release` therefore exposes
`/usr/lib/soraos/write-release` and `/usr/lib/soraos/add-repo`; the one-shot
live setup hook calls both explicitly. Installed systems get the same helpers
from `soraos-release.install` on install and upgrade.

Permanent libalpm hooks live in `/usr/share/libalpm/hooks/`, not
`/etc/pacman.d/hooks/`, because archiso deletes build-only hooks from
`/etc/pacman.d/hooks/` after the package transaction.

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
  both `archlinux` and `soraos`. The live medium's `[soraos]` entries are
  therefore verifiable with the committed public key.
- The Arch mirrorlist hook has already uncommented HTTPS mirrors at build time.
- The live `[soraos]` repository is at `/opt/soraos/repo/$arch`.
- The live CoW space is raised to 4 GiB with `cow_spacesize=4G`.

## Build path

```
make check   static validation (packages, kernel names, repo wiring, branding)
make repo    makepkg → detached signatures → repo-add → signature verification
make iso     build-repo.sh (unless SORAOS_SKIP_REPO=1)
             └─ stage repo → mkarchiso 92 → squashfs → xorriso
make run     QEMU UEFI (run_archiso when available, plain QEMU otherwise)
```

archiso 92 supports unprivileged builds through
`unshare --map-auto --map-root-user`. The build script verifies this and falls
back to a privileged container only when requested.

## Installation path (M3)

Calamares will install from packages through the same repository definition,
not by copying the live squashfs. M3 depends on M2b's hosted signed mirror (or
another durable package source); a `file://` repository inside the live medium
is not a valid update source for an installed machine.

## Secure Boot

The live ISO is unsigned, so Secure Boot must be disabled until the signing
pipeline in [secureboot.md](secureboot.md) lands. M2a's package signing does
not change that. The Secure Boot chain is M4 and is optional; if it is
descoped, the documented requirement remains "Secure Boot off".
