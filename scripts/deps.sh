#!/usr/bin/env bash
# Print the packages needed to build and test SoraOS, and report what is
# already present. This script does not install anything.
set -euo pipefail

packages=(archiso qemu-desktop edk2-ovmf librsvg base-devel gnupg)
echo "Install the build/test toolchain with:"
echo
echo "  sudo pacman -S --needed ${packages[*]}"
echo

check() {
    local label="$1" path="$2"
    if [[ -e "$path" ]]; then
        printf '  ok      %-24s %s\n' "$label" "$path"
    else
        printf '  missing %-24s %s\n' "$label" "$path"
    fi
}

check mkarchiso "$(command -v mkarchiso || echo /usr/bin/mkarchiso)"
check run_archiso "$(command -v run_archiso || echo /usr/bin/run_archiso)"
check qemu "$(command -v qemu-system-x86_64 || echo /usr/bin/qemu-system-x86_64)"
check rsvg-convert "$(command -v rsvg-convert || echo /usr/bin/rsvg-convert)"
check makepkg "$(command -v makepkg || echo /usr/bin/makepkg)"
check repo-add "$(command -v repo-add || echo /usr/bin/repo-add)"
check gpg "$(command -v gpg || echo /usr/bin/gpg)"

ovmf_code=""
for candidate in \
    /usr/share/edk2/x64/OVMF_CODE.4m.fd \
    /usr/share/edk2/x64/OVMF.4m.fd \
    /usr/share/OVMF/OVMF_CODE.fd; do
    if [[ -f "$candidate" ]]; then
        ovmf_code="$candidate"
        break
    fi
done
check ovmf-code "${ovmf_code:-/usr/share/edk2/x64/OVMF_CODE.4m.fd}"

echo
echo "Note: archiso 92+ can run mkarchiso as a normal user through user"
echo "namespaces. No sudo is needed for 'make iso' once archiso is installed."
echo "The M2a package repo is built locally with makepkg/repo-add/gpg."
