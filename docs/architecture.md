# SoraOS architecture

## The layer model

```
┌──────────────────────────────────────────────────────────────┐
│ SoraOS                                                       │
│   branding · defaults · SoraAgent/SoraDesk · installer       │
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

## Update model

- Official Arch mirrors are the source of truth for the base system.
- `[soraos]` is an additional repository, ordered after `[core]` and `[extra]`.
  It contains only SoraOS packages: release/branding, keyring, mirrorlist,
  SoraAgent/SoraDesk integration, installer configuration, and Calamares.
- No `IgnorePkg`, no pinned kernel, no partial upgrades.
- `pacman -Syu` remains the only supported full-update path. A future
  "curated snapshot" option, if ever added, must move **all** repositories to a
  dated snapshot; it must not hold back individual packages.

## Package ownership

| Package | Purpose |
|---|---|
| `soraos-release` | `/etc/os-release`, `/etc/issue`, `/etc/lsb-release`, release metadata |
| `soraos-keyring` | public signing key for `[soraos]`, populated by `pacman-key` |
| `soraos-mirrorlist` | `[soraos]` server list |
| `soraos-branding` | wallpapers, look-and-feel, boot branding, icons |
| `soraos-desktop-meta` | Plasma + SoraOS desktop defaults |
| `soraos-installer` | Calamares configuration and branding |
| `sora-agent`, `sora-desk` | SoraPlatform products, installed from `[soraos]` |

The M1 live image uses an airootfs overlay plus a one-shot pacman hook for
things owned by Arch packages (`/etc/os-release`, `/etc/issue`,
`/etc/pacman.conf`). M2 replaces that with `soraos-release` and friends.

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
  from `90-soraos-setup.hook`. It writes distro identity files, creates the
  `sora` user, configures passwordless sudo, installs the live pacman config,
  and enables services. It then removes itself and its hook.
- Plasma Login Manager (`plasmalogin`) autologins `sora`; its greeter wallpaper
  is set in `/etc/plasmalogin.conf`.
- `pacman-init.service` initializes the pacman keyring on a tmpfs; the
  mirrorlist hook has already uncommented HTTPS mirrors at build time.
- The live CoW space is raised to 4 GiB with `cow_spacesize=4G`.

## Build path

```
make check   static validation (package resolution, kernel names, config drift)
make iso     mkarchiso 92 (unprivileged via user namespaces)
             └─ pacstrap → airootfs hooks → squashfs → xorriso
make run     QEMU UEFI (run_archiso when available, plain QEMU otherwise)
```

archiso 92 supports unprivileged builds through
`unshare --map-auto --map-root-user`. The build script verifies this and falls
back to a privileged container only when requested.

## Secure Boot

M1 is unsigned. The signing chain, shim vs. custom-key trade-offs, and the
integration plan are in [secureboot.md](secureboot.md).
