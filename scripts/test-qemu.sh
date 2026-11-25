#!/usr/bin/env bash
# Boot the newest built SoraOS ISO in QEMU.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="uefi"
SECUREBOOT=0

usage() {
    cat <<'EOF'
usage: scripts/test-qemu.sh [--uefi|--bios] [--secureboot]

  --uefi        boot with UEFI (default)
  --bios        boot with BIOS/SeaBIOS
  --secureboot  boot with UEFI Secure Boot enabled. The current ISO is
                unsigned, so firmware will refuse it until signing lands.
EOF
}

while (($#)); do
    case "$1" in
        --uefi) MODE="uefi" ;;
        --bios) MODE="bios" ;;
        --secureboot) SECUREBOOT=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

iso="$(find "$ROOT/out" -maxdepth 1 -name 'soraos-*.iso' -printf '%T@ %p\n' | sort -nr | head -1 | cut -d' ' -f2- || true)"
[[ -n "$iso" ]] || { echo "error: no built ISO in $ROOT/out (run make iso)" >&2; exit 1; }

if ((SECUREBOOT)) && ! command -v run_archiso >/dev/null 2>&1; then
    echo "error: --secureboot needs run_archiso (part of archiso) to provide a" >&2
    echo "       Secure Boot OVMF setup; plain QEMU would silently boot unsigned." >&2
    exit 1
fi

if ((SECUREBOOT)); then
    echo "warning: the M1 ISO is unsigned. Secure Boot will reject it until the"
    echo "         signing pipeline in docs/secureboot.md lands." >&2
fi

if command -v run_archiso >/dev/null 2>&1; then
    args=(-i "$iso")
    [[ "$MODE" == "bios" ]] && args=(-b "${args[@]}")
    ((SECUREBOOT)) && args=(-s "${args[@]}")
    exec run_archiso "${args[@]}"
fi

command -v qemu-system-x86_64 >/dev/null 2>&1 || {
    echo "error: neither run_archiso nor qemu-system-x86_64 found" >&2
    echo "install with: sudo pacman -S --needed archiso qemu-desktop edk2-ovmf" >&2
    exit 1
}

qemu=(qemu-system-x86_64 -machine q35 -m 4096 -smp 4 -no-reboot
      -device virtio-vga -device qemu-xhci -device usb-tablet
      -nic "user,model=virtio-net-pci")
[[ -w /dev/kvm ]] && qemu+=(-enable-kvm -cpu host)
qemu+=(-boot "order=d,menu=on" -cdrom "$iso" -serial "file:$ROOT/out/qemu-serial.log")

if [[ "$MODE" == "uefi" ]]; then
    code=""
    for candidate in \
        /usr/share/edk2/x64/OVMF_CODE.4m.fd \
        /usr/share/edk2/x64/OVMF.4m.fd \
        /usr/share/OVMF/OVMF_CODE.fd; do
        [[ -f "$candidate" ]] && { code="$candidate"; break; }
    done
    [[ -n "$code" ]] || { echo "error: OVMF firmware not found (install edk2-ovmf)" >&2; exit 1; }

    vars_src=""
    for candidate in \
        /usr/share/edk2/x64/OVMF_VARS.4m.fd \
        /usr/share/edk2/x64/OVMF_VARS.fd \
        /usr/share/OVMF/OVMF_VARS.fd; do
        [[ -f "$candidate" ]] && { vars_src="$candidate"; break; }
    done
    vars="$(mktemp --suffix=.OVMF_VARS.fd)"
    if [[ -n "$vars_src" ]]; then
        cp -- "$vars_src" "$vars"
        qemu+=(-drive "if=pflash,format=raw,readonly=on,file=$code"
               -drive "if=pflash,format=raw,file=$vars")
    else
        qemu+=(-drive "if=pflash,format=raw,readonly=on,file=$code")
    fi
fi

echo "Booting $iso ($MODE)... serial log: $ROOT/out/qemu-serial.log"
exec "${qemu[@]}"
