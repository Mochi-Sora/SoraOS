# Secure Boot on SoraOS

## Current state

The M1 ISO is **unsigned**. Firmware with Secure Boot enabled will refuse to
boot it, exactly as it does with the official Arch ISO. For M1, Secure Boot
must be disabled or set to setup mode.

Secure Boot is nevertheless a first-class requirement for SoraOS, not an
afterthought. This document records the options and the planned path so the
build and release pipeline can be shaped around it now.

## What "Secure Boot on" requires

Firmware trusts a set of keys in its `db`. A boot chain works only if every
loaded EFI binary is signed by a trusted key:

```
firmware db ──verifies──> boot loader ──verifies──> kernel (or UKI)
```

There are three practical ways for an independent distro to satisfy this.

### 1. Custom SoraOS keys (recommended first step)

- Generate an offline SoraOS Secure Boot key pair (`sbctl` or `openssl` +
  `sbsign`).
- Sign `systemd-bootx64.efi` and `vmlinuz-linux-lts` (or a Unified Kernel
  Image) at build or release time.
- Publish the public certificate and document enrolling it in firmware
  ("Enroll key from file" / custom mode), or enroll it with `sbctl`.
- Works on any firmware that allows custom keys. No Microsoft involvement.
- Downside: one manual enrollment step per machine, and firmware updates may
  reset `db`.

This is the lowest-risk path and the one to implement first.

### 2. Shim + MOK (for stock firmware)

- Ship a Microsoft-signed `shim` as the first-stage loader.
- Shim carries the SoraOS vendor certificate and verifies a signed second stage
  (GRUB or systemd-boot).
- The kernel is signed by SoraOS; users enroll the SoraOS key once through
  MokManager (MOK).
- Works with Secure Boot on out of the box, including firmware that only
  trusts the Microsoft UEFI CA.
- Downside: shim review/signing process, a larger boot chain, and MOK
  enrollment UX.

This is the path for a public release that "just boots" on stock hardware.

### 3. Microsoft UEFI CA signing of the bootloader

Direct signing by Microsoft is expensive, slow, and aimed at vendors. Not
recommended for this project.

## Recommended plan

1. **M1/M2:** keep the ISO unsigned; document that Secure Boot must be off.
   Do not block the live/install work on signing.
2. **M3:** ship Calamares and the installable system unsigned; signing does
   not block the installer milestone.
3. **M4:** add `secureboot/` tooling:
   - `secureboot-keygen.sh` — create `db.key`/`db.crt` offline, gitignored.
   - `secureboot-sign.sh` — sign the EFI bootloader and kernel/UKI after the
     package transaction, without copying private keys into the airootfs.
   - A `--secureboot` build flag that stages only signed public artifacts.
4. **M4:** test with `run_archiso -s` against an OVMF NVRAM that has the
   SoraOS certificate enrolled. Automate the enrollment in the test harness.
5. **Post-1.0:** evaluate shim + MOK for stock-firmware support.

## Pipeline constraints

- **Private keys never enter the repository, the airootfs, or the ISO.**
  Sign on the build host or in CI, using a secret mount or hardware token.
- Sign **after** pacman has installed the exact kernel/bootloader versions
  used in the image. Version skew between a signed kernel and its modules is a
  boot failure.
- Prefer a **Unified Kernel Image** (kernel + initramfs + cmdline in one PE
  binary) for the installed system: one signature covers the whole early boot
  path and works cleanly with `systemd-boot` and `sbctl`.
- Keep the public certificate and enrollment instructions in
  `soraos-keyring`/docs so users can verify what they are trusting.
- Re-sign every kernel and bootloader update. On an installed system this is a
  pacman hook; on the ISO it is part of the release build.

## Testing Secure Boot

`run_archiso -s` boots OVMF with Secure Boot enabled. An unsigned ISO is
expected to fail. To test a signed image:

1. Boot a Linux VM with OVMF and enroll `db.crt` into the firmware `db`
   (`sbctl enroll-keys --microsoft` or firmware setup).
2. Boot the signed SoraOS ISO with `run_archiso -s`.
3. Verify with `bootctl status` / `mokutil --sb-state` inside the live session.

The CI job should assert both: the unsigned ISO is rejected, and the signed
ISO reaches the live session.
