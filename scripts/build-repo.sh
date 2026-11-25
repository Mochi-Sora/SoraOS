#!/usr/bin/env bash
# Build the SoraOS packages, sign them, and refresh the local repository.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$ROOT/repo/x86_64"
GNUPGHOME="${SORAOS_GNUPGHOME:-$ROOT/repo/keys/gnupg}"
export GNUPGHOME
KEYID_FILE="$ROOT/repo/keys/keyid"

die() { echo "error: $*" >&2; exit 1; }

command -v makepkg >/dev/null 2>&1 || die "makepkg not found; install base-devel"
command -v repo-add >/dev/null 2>&1 || die "repo-add not found; install pacman"
command -v gpg >/dev/null 2>&1 || die "gpg not found; install gnupg"
command -v npm >/dev/null 2>&1 || die "npm not found; install nodejs npm (SoraDesk source build)"
command -v cargo >/dev/null 2>&1 || die "cargo not found; install rust (SoraDesk source build)"
python -c 'import build, installer' >/dev/null 2>&1 \
    || die "python-build/python-installer not found; install them (Python package builds)"
[[ -f "$KEYID_FILE" ]] || die "no signing key; run scripts/gen-test-key.sh first"
KEYID="$(cat "$KEYID_FILE")"

rm -rf "$REPO_DIR"
mkdir -p "$REPO_DIR"

for pkgbuild in "$ROOT"/packages/*/PKGBUILD; do
    pkgdir="$(dirname "$pkgbuild")"
    echo "==> building $(basename "$pkgdir")"
    (
        cd "$pkgdir"
        PKGDEST="$REPO_DIR" makepkg --noconfirm --nodeps --force --cleanbuild --clean
    )
done

mapfile -t packages < <(find "$REPO_DIR" -maxdepth 1 -name '*.pkg.tar.zst' -print | sort)
((${#packages[@]} > 0)) || die "no packages were built"

for package in "${packages[@]}"; do
    gpg --batch --yes --local-user "$KEYID" --detach-sign --no-armor "$package"
done

repo-add --sign --key "$KEYID" "$REPO_DIR/soraos.db.tar.gz" "${packages[@]}"

for db in "$REPO_DIR/soraos.db.tar.gz" "$REPO_DIR/soraos.files.tar.gz"; do
    gpg --batch --verify "$db.sig" "$db"
done
for package in "${packages[@]}"; do
    gpg --batch --verify "$package.sig" "$package"
done

echo
echo "Repository: $REPO_DIR"
printf '  %s\n' "${packages[@]##*/}"
