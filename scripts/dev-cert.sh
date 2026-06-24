#!/usr/bin/env bash
# Creates a STABLE self-signed code-signing certificate in your login keychain.
#
# Why: macOS ties Accessibility / Input Monitoring / Microphone grants to an
# app's code-signing identity. Ad-hoc signing (`-`) produces a new identity on
# every build, so those grants never stick and the toggles appear to do nothing.
# A stable self-signed identity fixes this — grant once, rebuild freely.
set -euo pipefail

IDENTITY="${1:-Looped Whisper Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "✓ Code-signing identity '$IDENTITY' already exists."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/openssl.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = v3
prompt = no
[ dn ]
CN = $IDENTITY
[ v3 ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/openssl.cnf" >/dev/null 2>&1

# `-legacy` + a password: macOS Security can't import OpenSSL 3's default
# PKCS12 (SHA-256 MAC) with an empty password.
P12PASS="whisper"
openssl pkcs12 -export -legacy -out "$TMP/identity.p12" \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -passout pass:"$P12PASS" >/dev/null 2>&1

# Import key+cert and pre-authorize codesign to use it without prompting.
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$P12PASS" -T /usr/bin/codesign >/dev/null

echo "✓ Created code-signing identity '$IDENTITY' in your login keychain."
echo "  Now rebuild (make build) and grant permissions once — they'll persist."
