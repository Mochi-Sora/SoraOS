#!/usr/bin/env bash
# Static validation of the SoraOS archiso profile. Catches the mistakes that
# otherwise only show up 10 minutes into an ISO build.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail=0
note() { printf '  ok      %s\n' "$*"; }
bad()  { printf '  FAIL    %s\n' "$*"; fail=1; }

echo "== profile =="
# mkarchiso declares this associative array before sourcing the profile, so a
# plain `file_permissions=(...)` assignment in profiledef.sh updates it.
declare -A file_permissions=()
# shellcheck disable=SC1091
source iso/profiledef.sh
for var in iso_name iso_label iso_publisher iso_application iso_version \
           install_dir arch bootmodes pacman_conf airootfs_image_type; do
    if [[ -n "${!var:-}" ]]; then
        note "$var=${!var}"
    else
        bad "$var is empty or unset"
    fi
done
if [[ "$install_dir" =~ ^[a-z0-9]+$ && ${#install_dir} -le 30 ]]; then
    note "install_dir is valid"
else
    bad "install_dir must be lowercase alphanumeric, at most 30 chars"
fi

for mode in "${bootmodes[@]}"; do
    case "$mode" in
        bios.syslinux|uefi.systemd-boot|uefi.grub) note "bootmode $mode" ;;
        *) bad "unknown bootmode $mode" ;;
    esac
done

echo "== package list =="
if command -v pacman >/dev/null 2>&1; then
    mapfile -t pkgs < <(sed '/^\s*#/d;/^\s*$/d' iso/packages.x86_64)
    missing=()
    for pkg in "${pkgs[@]}"; do
        pacman -Si "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done
    if ((${#missing[@]})); then
        bad "packages not found in the sync DB: ${missing[*]}"
    else
        note "${#pkgs[@]} packages resolve"
    fi
    for required in linux-lts mkinitcpio mkinitcpio-archiso plasma-meta plasma-login-manager syslinux; do
        if printf '%s\n' "${pkgs[@]}" | grep -qx "$required"; then
            note "required package $required"
        else
            bad "missing required package $required"
        fi
    done
else
    echo "  skip    pacman not available"
fi

echo "== kernel wiring =="
mkinitcpio_conf="iso/airootfs/etc/mkinitcpio.conf.d/archiso.conf"
if [[ -f "$mkinitcpio_conf" ]] && grep -q 'HOOKS=.*\barchiso\b' "$mkinitcpio_conf"; then
    note "initramfs includes the archiso hook"
else
    bad "missing $mkinitcpio_conf or its archiso HOOKS entry (ISO will not find its root)"
fi
if grep -REq 'vmlinuz-linux([^-]|$)' iso/efiboot iso/syslinux; then
    bad "boot config references vmlinuz-linux (non-LTS)"
else
    note "boot configs do not reference the non-LTS kernel"
fi
if grep -Rq 'vmlinuz-linux-lts' iso/efiboot iso/syslinux; then
    note "boot configs reference vmlinuz-linux-lts"
else
    bad "boot configs do not reference vmlinuz-linux-lts"
fi
if grep -Rq 'initramfs-linux-lts.img' iso/efiboot iso/syslinux; then
    note "boot configs reference the LTS initramfs"
else
    bad "boot configs do not reference the LTS initramfs"
fi

default_entry="$(awk '/^default /{print $2; exit}' iso/efiboot/loader/loader.conf)"
if [[ -f "iso/efiboot/loader/entries/$default_entry" ]]; then
    note "loader default $default_entry exists"
else
    bad "loader default $default_entry is missing"
fi

for f in iso/efiboot/loader/entries/*.conf iso/syslinux/*.cfg; do
    if grep -q '%KERNEL_PARAMS%' "$f"; then
        note "$f applies kernel params"
    else
        bad "$f does not reference %KERNEL_PARAMS%"
    fi
done

echo "== live boot behavior =="
# mkarchiso writes /etc/machine-id as "uninitialized", which makes
# systemd-firstboot prompt on the console and can block the graphical target.
kparams_var="kernel_params_$arch"
if [[ -n "${!kparams_var:-}" ]] && grep -qw 'systemd.firstboot=no' <<<"${!kparams_var}"; then
    note "$kparams_var disables systemd-firstboot"
else
    bad "$kparams_var must contain systemd.firstboot=no"
fi
firstboot_mask="iso/airootfs/etc/systemd/system/systemd-firstboot.service"
if [[ "$(readlink -- "$firstboot_mask" 2>/dev/null)" == "/dev/null" ]]; then
    note "systemd-firstboot.service is masked"
else
    bad "$firstboot_mask must be a symlink to /dev/null"
fi

echo "== pacman config =="
if cmp -s iso/pacman.conf iso/airootfs/etc/soraos/pacman.conf; then
    note "build and live pacman.conf are identical"
else
    bad "iso/pacman.conf and iso/airootfs/etc/soraos/pacman.conf differ"
fi
if grep -q '^\[core\]' iso/pacman.conf; then
    note "core repo enabled"
else
    bad "core repo missing"
fi
if grep -q '^\[extra\]' iso/pacman.conf; then
    note "extra repo enabled"
else
    bad "extra repo missing"
fi

echo "== live image =="
for path in \
    iso/airootfs/etc/plasmalogin.conf \
    iso/airootfs/etc/sudoers.d/10-sora-live \
    iso/airootfs/etc/pacman.d/hooks/90-soraos-setup.hook \
    iso/airootfs/usr/local/bin/soraos-airootfs-setup \
    iso/airootfs/etc/systemd/system/pacman-init.service \
    iso/airootfs/etc/systemd/system/systemd-firstboot.service \
    iso/airootfs/etc/systemd/system/etc-pacman.d-gnupg.mount \
    iso/airootfs/etc/systemd/system/livecd-talk.service \
    iso/airootfs/usr/local/bin/livecd-sound \
    iso/airootfs/usr/share/wallpapers/SoraOS/metadata.json \
    iso/airootfs/usr/share/wallpapers/SoraOS/contents/images/3840x2160.png \
    iso/airootfs/usr/share/plasma/look-and-feel/org.soraos.desktop/metadata.json \
    iso/syslinux/splash.png; do
    if [[ -e "$path" ]]; then
        note "$path"
    else
        bad "missing $path"
    fi
done

if grep -q '^User=sora$' iso/airootfs/etc/plasmalogin.conf; then
    note "Plasma Login Manager autologins sora"
else
    bad "plasmalogin.conf does not autologin sora"
fi
if grep -q '^Session=plasma.desktop$' iso/airootfs/etc/plasmalogin.conf; then
    note "Plasma session selected"
else
    bad "plasmalogin.conf does not select plasma.desktop"
fi

plm_image="$(sed -n 's|^Image=file://||p' iso/airootfs/etc/plasmalogin.conf | head -1)"
if [[ -n "$plm_image" && -f "iso/airootfs$plm_image" ]]; then
    note "greeter wallpaper exists: $plm_image"
else
    bad "greeter wallpaper missing: ${plm_image:-unset}"
fi

laf_id="$(sed -n 's/.*"Id": "\([^"]*\)".*/\1/p' \
    iso/airootfs/usr/share/plasma/look-and-feel/org.soraos.desktop/metadata.json | head -1)"
if [[ -n "$laf_id" ]] && grep -q "LookAndFeelPackage=$laf_id" iso/airootfs/etc/skel/.config/kdeglobals; then
    note "skel selects look-and-feel $laf_id"
else
    bad "skel look-and-feel does not match the installed package (${laf_id:-unset})"
fi

if grep -q 'NOPASSWD' iso/airootfs/etc/sudoers.d/10-sora-live; then
    note "live sudo is passwordless"
else
    bad "live sudoers entry is missing NOPASSWD"
fi

if grep -q -- '-s /bin/bash sora' iso/airootfs/usr/local/bin/soraos-airootfs-setup; then
    note "live user creation hook present"
else
    bad "live user creation hook missing"
fi

echo "== file_permissions =="
for path in "${!file_permissions[@]}"; do
    if [[ -e "iso/airootfs$path" ]]; then
        note "$path"
    else
        bad "file_permissions entry has no file: $path"
    fi
done
# mkarchiso uses --no-preserve=mode when copying airootfs, so anything executed
# directly by systemd or the shell needs an explicit mode here.
for path in /usr/local/bin/livecd-sound /usr/local/bin/soraos-airootfs-setup; do
    if [[ "${file_permissions[$path]:-}" == *:755 ]]; then
        note "$path is executable in the image"
    else
        bad "$path must be listed as 0:0:755 in file_permissions"
    fi
done
# mkarchiso sources the profile inside a function. Verify the array survives
# that scope instead of being shadowed by a `declare -A` in profiledef.sh.
if (
    declare -A file_permissions=()
    _load_profiledef() { . iso/profiledef.sh; }
    _load_profiledef
    ((${#file_permissions[@]} > 0))
); then
    note "file_permissions survives function-scoped sourcing"
else
    bad "file_permissions is function-local; use a plain assignment in profiledef.sh"
fi

echo "== scripts =="
while IFS= read -r script; do
    if bash -n "$script"; then
        note "bash -n $script"
    else
        bad "bash -n $script"
    fi
done < <(find scripts iso/airootfs/usr/local/bin -type f \
    \( -name '*.sh' -o -name 'soraos-airootfs-setup' -o -name 'livecd-sound' \) | sort)

if command -v shellcheck >/dev/null 2>&1; then
    while IFS= read -r script; do
        if shellcheck -x "$script"; then
            note "shellcheck $script"
        else
            bad "shellcheck $script"
        fi
    done < <(find scripts -type f -name '*.sh' | sort)
else
    echo "  skip    shellcheck not installed"
fi

echo
if ((fail)); then
    echo "Profile check FAILED." >&2
    exit 1
fi
echo "Profile check passed."
