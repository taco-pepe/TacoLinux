#!/usr/bin/env bash
#
# build-xbps.sh -- install the XBPS package manager into rootfs/ alongside Nix.
#
# XBPS (X Binary Package System) is installed from nixpkgs into the default Nix
# profile, so it is available on both base and desktop builds without requiring
# the desktop closure.
#
# This script follows the same chroot/nixpkgs pattern as build-desktop.sh.
# It needs root (to chroot/mount).  Run it more than once safely.
#
# Env:
#   ROOTFS          source tree                     (default: <repo>/rootfs)
#   NIXPKGS_VERSION pinned nixpkgs (bump with hash) (default: same as build-desktop.sh)
#   NIXPKGS_URL     tarball URL
#   NIXPKGS_DIR     local cache dir                 (default: <repo>/.cache/<version>)
#   PROFILE         target Nix profile              (default: /nix/var/nix/profiles/default)
#   CAP=0           disable CPU/memory caps
#
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ROOTFS=${ROOTFS:-$REPO_ROOT/rootfs}

NIXPKGS_VERSION=${NIXPKGS_VERSION:-nixpkgs-26.11pre1109744.4fe25e12eb9f}
NIXPKGS_URL=${NIXPKGS_URL:-https://releases.nixos.org/nixpkgs/$NIXPKGS_VERSION/nixexprs.tar.zst}
NIXPKGS_DIR=${NIXPKGS_DIR:-$REPO_ROOT/.cache/$NIXPKGS_VERSION}

PROFILE=${PROFILE:-/nix/var/nix/profiles/default}
NIXBIN=/nix/var/nix/profiles/default/bin
NIXPKGS_IN_CHROOT=/nixpkgs

CPUSET=${CPUSET:-0-5}
CPUQUOTA=${CPUQUOTA:-600%}
MEMCAP=${MEMCAP:-6G}
CAP=${CAP:-1}

log() { printf '\033[1;35m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ -d "$ROOTFS" ] || die "rootfs not found at $ROOTFS"
[ "$(id -u)" -eq 0 ] || command -v sudo >/dev/null || die "need root or sudo to chroot"

asroot() { if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi; }

asroot chroot "$ROOTFS" test -x "$NIXBIN/nix-env" \
  || die "rootfs is missing the bundled Nix ($NIXBIN/nix-env)"

MOUNTS=()
cleanup() {
  local i
  for ((i = ${#MOUNTS[@]} - 1; i >= 0; i--)); do
    asroot umount -R "${MOUNTS[i]}" 2>/dev/null || true
  done
}
trap cleanup EXIT

mount_chroot() {
  local m
  asroot mkdir -p "$ROOTFS"/{proc,sys,dev,run}
  for m in proc sys dev; do
    if ! mountpoint -q "$ROOTFS/$m"; then
      case $m in
        proc) asroot mount -t proc proc "$ROOTFS/proc" ;;
        sys)  asroot mount -t sysfs sysfs "$ROOTFS/sys" ;;
        dev)  asroot mount --rbind /dev "$ROOTFS/dev" ;;
      esac
      MOUNTS+=("$ROOTFS/$m")
    fi
  done
  asroot mkdir -p "$ROOTFS$NIXPKGS_IN_CHROOT"
  if ! mountpoint -q "$ROOTFS$NIXPKGS_IN_CHROOT"; then
    asroot mount --rbind "$NIXPKGS_DIR" "$ROOTFS$NIXPKGS_IN_CHROOT"
    MOUNTS+=("$ROOTFS$NIXPKGS_IN_CHROOT")
  fi
  [ -s "$ROOTFS/etc/resolv.conf" ] || asroot cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf"
}

in_chroot() {
  if [ "$CAP" = 1 ] && command -v systemd-run >/dev/null 2>&1; then
    asroot systemd-run --scope -q \
      -p CPUQuota="$CPUQUOTA" -p MemoryMax="$MEMCAP" -p MemorySwapMax=0 \
      -- nice -n 19 ionice -c 3 taskset -c "$CPUSET" \
      chroot "$ROOTFS" "$@"
  else
    asroot chroot "$ROOTFS" "$@"
  fi
}

fetch_nixpkgs() {
  if [ -f "$NIXPKGS_DIR/default.nix" ]; then
    log "using cached nixpkgs at $NIXPKGS_DIR"
    return
  fi
  log "fetching $NIXPKGS_VERSION"
  mkdir -p "$NIXPKGS_DIR"
  local tmp; tmp=$(mktemp -d)
  curl -4 -fsSL -o "$tmp/nixpkgs.tar.zst" "$NIXPKGS_URL"
  tar --zstd -xf "$tmp/nixpkgs.tar.zst" -C "$NIXPKGS_DIR" --strip-components=1
  rm -rf "$tmp"
  [ -f "$NIXPKGS_DIR/default.nix" ] || die "nixpkgs extraction failed"
}

log "TacoLinux XBPS build (alongside Nix)"
log "rootfs:  $ROOTFS"
log "profile: $PROFILE"

fetch_nixpkgs
mount_chroot

# Ensure bootstrap closure is registered if DB is missing/uninitialized.
if [ ! -s "$ROOTFS/nix/var/nix/db/db.sqlite" ] ||
   [ "$(stat -c%s "$ROOTFS/nix/var/nix/db/db.sqlite" 2>/dev/null || echo 0)" -lt 4096 ]; then
  log "loading bootstrap Nix DB from .reginfo"
  asroot chroot "$ROOTFS" "$NIXBIN/nix-store" --load-db < "$ROOTFS/nix/.reginfo"
fi

log "installing xbps (may download/build on first run)"
in_chroot "$NIXBIN/nix-env" -f "$NIXPKGS_IN_CHROOT" -iA xbps \
  --profile "$PROFILE" --option cores 4 --option max-jobs 2 \
  --option build-users-group '' \
  2> >(grep -v "build-users-group" >&2)

# Basic sanity check inside the chroot/profile.
if ! asroot chroot "$ROOTFS" test -x "$PROFILE/bin/xbps-install"; then
  log "warning: $PROFILE/bin/xbps-install not found after install"
else
  log "xbps-install: $PROFILE/bin/xbps-install"
fi

log "done: XBPS installed in $PROFILE"
