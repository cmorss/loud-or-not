#!/usr/bin/env bash
set -euo pipefail

# Creates a self-signed code signing identity in the login keychain.
#
# Ad-hoc signatures make the app's designated requirement depend on the binary hash,
# so every rebuild looks like a brand new app to macOS and the microphone permission
# has to be granted again. Signing with a stable certificate makes the designated
# requirement depend on the certificate instead, and the grant survives rebuilds.

IDENTITY_NAME="Loud or Not Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY_NAME"; then
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=$IDENTITY_NAME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

# macOS cannot read the PKCS#12 encryption OpenSSL 3 picks by default.
openssl pkcs12 -export -out "$WORK/identity.p12" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -passout pass:loudornot \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1

security import "$WORK/identity.p12" -k "$KEYCHAIN" -P loudornot -T /usr/bin/codesign

echo "Created code signing identity: $IDENTITY_NAME"
echo "If macOS asks whether codesign may use the key, choose Always Allow."
