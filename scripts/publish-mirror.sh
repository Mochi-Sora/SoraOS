#!/usr/bin/env bash
# Publish the signed repository to a static mirror directory.
#
# The default target is the SoraOfficialWebsite GitHub Pages checkout. The
# script dereferences the repo-add symlinks so the mirror works over plain
# HTTP (GitHub Pages does not serve symlinked files).
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$ROOT/repo/x86_64"
TARGET="${SORAOS_MIRROR_DIR:-$ROOT/../SoraOfficialWebsite/repo/x86_64}"
GNUPGHOME="${SORAOS_GNUPGHOME:-$ROOT/repo/keys/gnupg}"
export GNUPGHOME

die() { echo "error: $*" >&2; exit 1; }

[[ -f "$REPO_DIR/soraos.db.tar.gz" ]] || die "missing $REPO_DIR/soraos.db.tar.gz; run make repo"
[[ -f "$REPO_DIR/soraos.db.tar.gz.sig" ]] || die "repository database is unsigned"
[[ -n "${TARGET//\//}" && "$TARGET" != "/" ]] || die "refusing to use $TARGET as the mirror root"

# If the target is not already a mirror directory, require an explicit path.
if [[ -e "$TARGET" && ! -d "$TARGET" ]]; then
    die "$TARGET exists and is not a directory"
fi

# Verify the source before copying anything.
gpg --batch --verify "$REPO_DIR/soraos.db.tar.gz.sig" "$REPO_DIR/soraos.db.tar.gz"
gpg --batch --verify "$REPO_DIR/soraos.files.tar.gz.sig" "$REPO_DIR/soraos.files.tar.gz"
for package in "$REPO_DIR"/*.pkg.tar.zst; do
    gpg --batch --verify "$package.sig" "$package"
done

mkdir -p "$TARGET"

# Remove only generated repository files; leave any site README in place.
rm -f "$TARGET"/*.pkg.tar.zst "$TARGET"/*.pkg.tar.zst.sig
rm -f "$TARGET"/soraos.db "$TARGET"/soraos.db.sig
rm -f "$TARGET"/soraos.files "$TARGET"/soraos.files.sig

cp -L "$REPO_DIR/soraos.db" "$TARGET/soraos.db"
cp -L "$REPO_DIR/soraos.db.sig" "$TARGET/soraos.db.sig"
cp -L "$REPO_DIR/soraos.files" "$TARGET/soraos.files"
cp -L "$REPO_DIR/soraos.files.sig" "$TARGET/soraos.files.sig"
for package in "$REPO_DIR"/*.pkg.tar.zst; do
    cp "$package" "$TARGET/"
    cp "$package.sig" "$TARGET/"
done

# Re-verify the published copy, including the dereferenced database files.
gpg --batch --verify "$TARGET/soraos.db.sig" "$TARGET/soraos.db"
gpg --batch --verify "$TARGET/soraos.files.sig" "$TARGET/soraos.files"
for package in "$TARGET"/*.pkg.tar.zst; do
    gpg --batch --verify "$package.sig" "$package"
done

echo "Published signed repository to: $TARGET"
echo "Commit and push that directory with the website repository."
