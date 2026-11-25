#!/usr/bin/env bash
# Create the local M2a test signing key and publish its public half.
#
# This is deliberately a TEST key. The private key stays in repo/keys/ (ignored
# by git); the public key is committed in the soraos-keyring package. Replace
# both with an offline production key before publishing a real repository.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GNUPGHOME="${SORAOS_GNUPGHOME:-$ROOT/repo/keys/gnupg}"
export GNUPGHOME
KEYRING_DIR="$ROOT/packages/soraos-keyring/files/usr/share/pacman/keyrings"
KEYID_FILE="$ROOT/repo/keys/keyid"

mkdir -p "$GNUPGHOME" "$KEYRING_DIR"
chmod 700 "$GNUPGHOME"

if [[ -f "$KEYID_FILE" ]]; then
    echo "Test signing key already present: $(cat "$KEYID_FILE")"
    exit 0
fi

gpg --batch --pinentry-mode loopback --passphrase '' \
    --quick-generate-key 'SoraOS Test Repository (M2a) <soraos@mochisora.local>' \
    rsa4096 sign 0

fingerprint="$(gpg --batch --with-colons --list-secret-keys \
    | awk -F: '/^fpr:/ { print $10; exit }')"
[[ -n "$fingerprint" ]] || { echo "error: could not read test key fingerprint" >&2; exit 1; }

gpg --batch --export "$fingerprint" >"$KEYRING_DIR/soraos.gpg"
printf '%s:4:\n' "$fingerprint" >"$KEYRING_DIR/soraos-trusted"
: >"$KEYRING_DIR/soraos-revoked"
printf '%s\n' "$fingerprint" >"$KEYID_FILE"

chmod 644 "$KEYRING_DIR/soraos.gpg" "$KEYRING_DIR/soraos-trusted" "$KEYRING_DIR/soraos-revoked"
echo "Created test signing key: $fingerprint"
echo "Private key: $GNUPGHOME (ignored by git)"
echo "WARNING: this is a test key. Replace it with an offline production key before publishing."
