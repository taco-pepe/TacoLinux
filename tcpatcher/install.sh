#!/bin/bash
# Install tcpatch into a target root tree.
# Usage: ./install.sh [DESTDIR]       (default: / — use a sandbox for image builds)
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${1:-${DESTDIR:-/}}"
DEST="${DEST%/}"   # empty means the real /; avoids //usr/... paths

install -Dm755 "$SRC/tcpatch" "$DEST/usr/lib/tcpatcher/tcpatch"
for f in "$SRC"/lib/*.sh; do
  install -Dm644 "$f" "$DEST/usr/lib/tcpatcher/lib/$(basename "$f")"
done
mkdir -p "$DEST/usr/local/bin"
ln -sfn ../../lib/tcpatcher/tcpatch "$DEST/usr/local/bin/tcpatch"

# The design puts the version in /usr/distro/version.cfg. Current TacoLinux
# images only have /etc/os-release, so seed the file from there if missing.
if [[ -f $DEST/etc/os-release && ! -f $DEST/usr/distro/version.cfg ]]; then
  ver="$(awk -F= '/^VERSION_ID=/ { gsub(/["\047]/, "", $2); print $2; exit }' "$DEST/etc/os-release")"
  if [[ -n $ver ]]; then
    mkdir -p "$DEST/usr/distro"
    printf 'VER=%s\n' "$ver" > "$DEST/usr/distro/version.cfg"
    printf 'Seeded %s/usr/distro/version.cfg (VER=%s)\n' "$DEST" "$ver"
  fi
fi

printf 'Installed tcpatch into %s\n' "${DEST:-/}"
