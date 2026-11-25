#!/usr/bin/env bash
# Build the SoraOS live ISO.
#
# archiso 92+ can build unprivileged using user namespaces, so this script does
# not require root when mkarchiso is installed on the host. If mkarchiso is not
# available it can fall back to a privileged archlinux container.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="$ROOT/iso"
WORK="$ROOT/work"
OUT="$ROOT/out"
ENGINE="auto"
REPO_DIR="$ROOT/repo/x86_64"
STAGED_REPO="$PROFILE/airootfs/opt/soraos/repo"

usage() {
    cat <<'EOF'
usage: scripts/build.sh [options]

options:
  --container   build inside an archlinux container (podman/docker)
  --host        build with the host's mkarchiso (default when available)
  -h, --help    show this help
EOF
}

while (($#)); do
    case "$1" in
        --container) ENGINE="container" ;;
        --host) ENGINE="host" ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

die() { echo "error: $*" >&2; exit 1; }

# Stable timestamps make the ISO label/version reproducible for a given commit.
if [[ -z "${SOURCE_DATE_EPOCH:-}" ]]; then
    if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        # A fresh repo can be inside a work tree but still have no commits.
        SOURCE_DATE_EPOCH="$(git -C "$ROOT" log -1 --format=%ct 2>/dev/null || date +%s)"
    else
        SOURCE_DATE_EPOCH="$(date +%s)"
    fi
fi
export SOURCE_DATE_EPOCH

[[ -f "$PROFILE/profiledef.sh" ]] || die "missing $PROFILE/profiledef.sh"
[[ -f "$PROFILE/packages.x86_64" ]] || die "missing $PROFILE/packages.x86_64"

mkdir -p "$OUT" "$ROOT/.cache/pacman/pkg"

# M2a: build, sign, and stage the local [soraos] repository. Set
# SORAOS_SKIP_REPO=1 to reuse an existing repo during ISO-only iteration.
if [[ "${SORAOS_SKIP_REPO:-0}" != "1" ]]; then
    "$ROOT/scripts/build-repo.sh"
fi
[[ -d "$REPO_DIR" ]] || die "missing $REPO_DIR; run scripts/build-repo.sh"

rm -rf "$STAGED_REPO"
mkdir -p "$STAGED_REPO"
cp -a "$REPO_DIR" "$STAGED_REPO/"
cleanup_staged_repo() { rm -rf "$STAGED_REPO"; }
trap cleanup_staged_repo EXIT

# Rootless builds cannot write the host's /var/cache/pacman/pkg. Give mkarchiso
# a build-only pacman config with a repo-local cache.
BUILD_PACMAN_CONF="$ROOT/.cache/pacman.conf"
sed "/^\[options\]/a CacheDir = $ROOT/.cache/pacman/pkg" \
    "$PROFILE/pacman.conf" >"$BUILD_PACMAN_CONF"
# The build host does not trust the local test key; build-repo.sh verifies
# every package and the database signature. The live system uses Required.
printf '\n[soraos]\nSigLevel = Never\nServer = file://%s\n' \
    "$REPO_DIR" >>"$BUILD_PACMAN_CONF"

# The container sees the checkout under /build, not at the host path.
CONTAINER_PACMAN_CONF="$ROOT/.cache/pacman-container.conf"
cp "$PROFILE/pacman.conf" "$CONTAINER_PACMAN_CONF"
printf '\n[soraos]\nSigLevel = Never\nServer = file:///build/repo/x86_64\n' \
    >>"$CONTAINER_PACMAN_CONF"

# Never silently reuse a stale work directory: mkarchiso's -r only removes a
# work directory it created itself.
if [[ -e "$WORK" ]]; then
    if [[ -O "$WORK" ]]; then
        echo "Removing stale $WORK..."
        rm -rf -- "$WORK"
    else
        die "$WORK exists and is not owned by you. Check 'findmnt' for stale
bind mounts, then remove it with sudo before building."
    fi
fi

run_container() {
    local engine
    if command -v podman >/dev/null 2>&1; then
        engine=podman
    elif command -v docker >/dev/null 2>&1; then
        engine=docker
    else
        die "no container engine found; install archiso or podman/docker"
    fi

    echo "Building in an archlinux container with $engine..."
    "$engine" run --rm -it --privileged \
        --security-opt label=disable \
        -e SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
        -v "$ROOT:/build:Z" \
        -w /build \
        docker.io/archlinux:latest \
        bash -lc '
            set -euo pipefail
            pacman -Syu --noconfirm --needed archiso
            mkarchiso -v -r -C /build/.cache/pacman-container.conf -w /build/work -o /build/out /build/iso
        '
}

run_host() {
    command -v mkarchiso >/dev/null 2>&1 || die \
        "mkarchiso not found. Install it with: sudo pacman -S --needed archiso"

    if ((EUID == 0)); then
        echo "warning: building as root; archiso recommends an unprivileged build" >&2
    elif ! unshare --map-auto --map-root-user -- true >/dev/null 2>&1; then
        die "user namespaces are unavailable; rerun as root or use --container"
    fi

    if command -v pacman >/dev/null 2>&1; then
        echo "archiso: $(pacman -Q archiso 2>/dev/null || echo 'unknown')"
    fi

    mkarchiso -v -r -C "$BUILD_PACMAN_CONF" -w "$WORK" -o "$OUT" "$PROFILE"
}

case "$ENGINE" in
    container) run_container ;;
    host) run_host ;;
    auto)
        if command -v mkarchiso >/dev/null 2>&1; then
            run_host
        elif command -v podman >/dev/null 2>&1 || command -v docker >/dev/null 2>&1; then
            run_container
        else
            die "mkarchiso not found. Install it with: sudo pacman -S --needed archiso
(or install podman/docker and rerun with --container)"
        fi
        ;;
esac

iso="$(find "$OUT" -maxdepth 1 -name 'soraos-*.iso' -printf '%T@ %p\n' | sort -nr | head -1 | cut -d' ' -f2-)"
if [[ -n "$iso" ]]; then
    (cd "$OUT" && sha256sum "$(basename "$iso")" > "$(basename "$iso").sha256")
    echo
    echo "Built: $iso"
    echo "SHA256: $(cut -d' ' -f1 "$iso.sha256")"
fi
