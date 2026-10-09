#!/bin/bash
# One-time: create a stable self-signed code-signing identity in its own keychain.
# A stable identity keeps macOS Accessibility permission across auto-updates (ad-hoc signing would reset it each time).
set -euo pipefail
KC="$HOME/Library/Keychains/spacegrab-signing.keychain-db"
PW="spacegrab"
NAME="SpaceGrab Local Signing"
if [ -f "$KC" ] && security find-identity -p codesigning "$KC" | grep -q "$NAME"; then echo "Signing identity already exists"; exit 0; fi
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cat > "$T/o.cnf" <<CNF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout "$T/k.pem" -out "$T/c.pem" -config "$T/o.cnf" 2>/dev/null
openssl pkcs12 -export -inkey "$T/k.pem" -in "$T/c.pem" -out "$T/id.p12" -passout pass:$PW -legacy 2>/dev/null || \
openssl pkcs12 -export -inkey "$T/k.pem" -in "$T/c.pem" -out "$T/id.p12" -passout pass:$PW
[ -f "$KC" ] || security create-keychain -p "$PW" "$KC"
security set-keychain-settings "$KC"
security unlock-keychain -p "$PW" "$KC"
security import "$T/id.p12" -k "$KC" -P "$PW" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$PW" "$KC" >/dev/null
echo "Created signing identity '$NAME'"
