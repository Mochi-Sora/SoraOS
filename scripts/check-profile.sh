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
local_pkgs=(soraos-keyring soraos-mirrorlist soraos-release soraos-branding soraos-desktop-meta python-questionary sora-agent sora-desk sora-desk-bridge)
if command -v pacman >/dev/null 2>&1; then
    mapfile -t pkgs < <(sed '/^\s*#/d;/^\s*$/d' iso/packages.x86_64)
    missing=()
    for pkg in "${pkgs[@]}"; do
        if printf '%s\n' "${local_pkgs[@]}" | grep -qx "$pkg"; then
            [[ -f "packages/$pkg/PKGBUILD" ]] || missing+=("$pkg (missing local PKGBUILD)")
        else
            pacman -Si "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
        fi
    done
    if ((${#missing[@]})); then
        bad "packages not found: ${missing[*]}"
    else
        note "${#pkgs[@]} packages resolve (including local soraos-*)"
    fi
    for required in linux-lts mkinitcpio mkinitcpio-archiso plasma-meta plasma-login-manager syslinux soraos-desktop-meta sora-agent sora-desk sora-desk-bridge; do
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
if grep -q '\[soraos\]' scripts/build.sh \
    && grep -q 'SigLevel = Never' scripts/build.sh; then
    note "build config adds the local soraos repo"
else
    bad "scripts/build.sh does not add the local soraos repo"
fi
if grep -q 'pacman-key --populate soraos' iso/airootfs/etc/systemd/system/pacman-init.service; then
    note "pacman-init trusts the soraos keyring"
else
    bad "pacman-init does not populate the soraos keyring"
fi
if grep -q '/usr/lib/soraos/write-release' iso/airootfs/usr/local/bin/soraos-airootfs-setup \
    && grep -q '/usr/lib/soraos/add-repo' iso/airootfs/usr/local/bin/soraos-airootfs-setup; then
    note "live setup applies the package-owned release/repo helpers"
else
    bad "live setup does not apply the release/repo helpers (pacstrap -N skips .install)"
fi

echo "== local repo =="
for pkg in "${local_pkgs[@]}"; do
    if [[ -f "packages/$pkg/PKGBUILD" ]]; then
        note "package source $pkg"
    else
        bad "missing packages/$pkg/PKGBUILD"
    fi
done
for script in scripts/build-repo.sh scripts/gen-test-key.sh scripts/publish-mirror.sh; do
    if [[ -x "$script" ]]; then
        note "$script is executable"
    else
        bad "$script is missing or not executable"
    fi
done
keyring_file="packages/soraos-keyring/files/usr/share/pacman/keyrings/soraos.gpg"
if [[ -s "$keyring_file" ]]; then
    note "public repo keyring is present"
else
    bad "missing $keyring_file (run scripts/gen-test-key.sh)"
fi
mirrorlist="packages/soraos-mirrorlist/files/etc/pacman.d/soraos-mirrorlist"
if [[ -f "$mirrorlist" ]] && grep -q '^Server = ' "$mirrorlist"; then
    note "soraos mirrorlist has a server entry"
else
    bad "missing or empty $mirrorlist"
fi
if grep -Fq "Server = https://mochi-sora.github.io/SoraOfficialWebsite/repo/\$arch" "$mirrorlist" \
    && grep -Fq "Server = file:///opt/soraos/repo/\$arch" "$mirrorlist"; then
    note "soraos mirrorlist has the hosted and local servers"
else
    bad "$mirrorlist must list the hosted mirror and the on-medium fallback"
fi
for path in \
    packages/soraos-release/files/usr/lib/soraos/write-release \
    packages/soraos-release/files/usr/lib/soraos/add-repo \
    packages/soraos-release/files/usr/share/libalpm/hooks/soraos-release.hook \
    packages/soraos-release/files/usr/share/libalpm/hooks/soraos-repo.hook \
    packages/soraos-release/soraos-release.install \
    packages/sora-desk/files/SoraDesk.desktop \
    packages/sora-desk/sora-desk.install; do
    if [[ -f "$path" ]]; then
        note "$path"
    else
        bad "missing $path"
    fi
done
for product in sora-agent sora-desk sora-desk-bridge; do
    if grep -q "'$product'" packages/soraos-desktop-meta/PKGBUILD; then
        note "desktop meta includes $product"
    else
        bad "packages/soraos-desktop-meta/PKGBUILD does not depend on $product"
    fi
done
if grep -q 'build --no-bundle' packages/sora-desk/PKGBUILD; then
    note "SoraDesk uses the Tauri production build"
else
    bad "SoraDesk must build with 'tauri build --no-bundle', not bare cargo"
fi
if grep -q 'websockets>=15,<18' packages/sora-desk-bridge/PKGBUILD; then
    note "bridge websockets guard is the tested Arch version"
else
    bad "bridge websockets guard is missing; verify the smoke suite before changing it"
fi
if grep -qx 'soraos-desktop-meta' iso/packages.x86_64 \
    && grep -qx 'sora-agent' iso/packages.x86_64 \
    && grep -qx 'sora-desk' iso/packages.x86_64 \
    && grep -qx 'sora-desk-bridge' iso/packages.x86_64; then
    note "live image installs the SoraOS product packages"
else
    bad "iso/packages.x86_64 does not install SoraAgent/SoraDesk"
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
    packages/soraos-branding/files/usr/share/wallpapers/SoraOS/metadata.json \
    packages/soraos-branding/files/usr/share/wallpapers/SoraOS/contents/images/3840x2160.png \
    packages/soraos-branding/files/usr/share/color-schemes/SoraOS.colors \
    packages/soraos-branding/files/usr/share/plasma/look-and-feel/org.soraos.desktop/metadata.json \
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
if [[ -n "$plm_image" && -f "packages/soraos-branding/files$plm_image" ]]; then
    note "greeter wallpaper exists in soraos-branding: $plm_image"
else
    bad "greeter wallpaper missing from soraos-branding: ${plm_image:-unset}"
fi

laf_id="$(sed -n 's/.*"Id": "\([^"]*\)".*/\1/p' \
    packages/soraos-branding/files/usr/share/plasma/look-and-feel/org.soraos.desktop/metadata.json | head -1)"
if [[ -n "$laf_id" ]] && grep -q "LookAndFeelPackage=$laf_id" packages/soraos-branding/files/etc/skel/.config/kdeglobals; then
    note "skel selects look-and-feel $laf_id"
else
    bad "skel look-and-feel does not match the installed package (${laf_id:-unset})"
fi

color_scheme="packages/soraos-branding/files/usr/share/color-schemes/SoraOS.colors"
if grep -q '^ColorScheme=SoraOS$' "$color_scheme" \
    && grep -q '^ColorScheme=SoraOS$' packages/soraos-branding/files/etc/skel/.config/kdeglobals \
    && grep -q '^ColorScheme=SoraOS$' packages/soraos-branding/files/usr/share/plasma/look-and-feel/org.soraos.desktop/contents/defaults; then
    note "skel and look-and-feel select the SoraOS color scheme"
else
    bad "SoraOS color scheme is not selected in skel and look-and-feel"
fi
if grep -q '^AccentColor=122,162,247$' packages/soraos-branding/files/etc/skel/.config/kdeglobals \
    && grep -q '^AccentColor=122,162,247$' packages/soraos-branding/files/usr/share/plasma/look-and-feel/org.soraos.desktop/contents/defaults; then
    note "accent color is the SoraPlatform blue"
else
    bad "accent color is not 122,162,247 in skel and look-and-feel"
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

echo "== branding =="
if cmp -s branding/sora-mark.svg packages/soraos-branding/files/usr/share/icons/hicolor/scalable/apps/soraos.svg \
    && cmp -s branding/sora-mark.svg packages/soraos-branding/files/usr/share/pixmaps/soraos.svg; then
    note "installed icons match branding/sora-mark.svg"
else
    bad "installed icons are stale; run scripts/build-branding.sh"
fi
if grep -q 'C 690 245' branding/sora-mark.svg; then
    note "SoraPlatform S mark in use"
else
    bad "branding/sora-mark.svg is not the SoraPlatform S mark"
fi
if grep -RqI 'M11 17h11v13h20V17h11v30H42V39H22v8H11V17Z' branding packages iso/airootfs; then
    bad "website placeholder H mark is still present"
else
    note "placeholder H mark is gone"
fi
if grep -RqI '#e789a0' branding packages iso/airootfs iso/syslinux README.md; then
    bad "old pink palette (#e789a0) is still present"
else
    note "branding uses the SoraPlatform palette"
fi
if grep -q 'ANSI_COLOR="38;2;122;162;247"' packages/soraos-release/files/usr/share/soraos/os-release; then
    note "os-release accent is platform blue"
else
    bad "os-release ANSI_COLOR is not the platform blue"
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
done < <(find scripts iso/airootfs/usr/local/bin packages \
    \( -path '*/pkg' -o -path '*/src' \) -prune -o \
    -type f \( -name '*.sh' -o -name '*.install' -o -name 'soraos-airootfs-setup' \
       -o -name 'livecd-sound' -o -path '*/usr/lib/soraos/*' \) -print | sort)

if command -v shellcheck >/dev/null 2>&1; then
    while IFS= read -r script; do
        if shellcheck -x "$script"; then
            note "shellcheck $script"
        else
            bad "shellcheck $script"
        fi
    done < <(find scripts packages \
        \( -path '*/pkg' -o -path '*/src' \) -prune -o \
        -type f \( -name '*.sh' -o -path '*/usr/lib/soraos/*' \) -print | sort)
else
    echo "  skip    shellcheck not installed"
fi

echo
if ((fail)); then
    echo "Profile check FAILED." >&2
    exit 1
fi
echo "Profile check passed."
