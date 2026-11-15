#!/usr/bin/env bash
#
# build-desktop.sh -- realize the TacoLinux desktop closure (SDDM + XFCE)
# into rootfs/.
#
# TacoLinux ships a small, self-contained Nix store (the "bootstrap" closure)
# committed to git.  The desktop environment is *not* committed: it is a
# ~2 GiB closure that would bloat the repository and every clone.  Instead
# this script builds it, and CI bakes the result into the published image.
#
# It is safe to run more than once: if the profile already exists and matches
# the package set, Nix does nothing.
#
# Everything runs inside a chroot of the target rootfs using the Nix that the
# rootfs already carries, so the closure is built with exactly the right
# glibc and dependencies -- no host contamination.
#
# Resource use is capped on purpose (this project is developed on a laptop):
#   CPUSET     cores to pin to            (default 0-5, i.e. 6 cores)
#   CPUQUOTA   systemd CPUQuota           (default 600%)
#   MEMCAP     systemd MemoryMax          (default 6G)
# Set CAP=0 to disable the caps (CI runners can afford the whole machine).
#
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ROOTFS=${ROOTFS:-$REPO_ROOT/rootfs}

# Pinned nixpkgs.  Bump NIXPKGS_VERSION and the hash together.
NIXPKGS_VERSION=${NIXPKGS_VERSION:-nixpkgs-26.11pre1109744.4fe25e12eb9f}
NIXPKGS_URL=${NIXPKGS_URL:-https://releases.nixos.org/nixpkgs/$NIXPKGS_VERSION/nixexprs.tar.zst}
# Keep the (re)download out of /tmp so a reboot does not throw it away.
NIXPKGS_DIR=${NIXPKGS_DIR:-$REPO_ROOT/.cache/$NIXPKGS_VERSION}

PROFILE=${PROFILE:-/nix/var/nix/profiles/desktop}
NIXBIN=/nix/var/nix/profiles/default/bin
NIXPKGS_IN_CHROOT=/nixpkgs

# The desktop closure.  Keep this list in sync with the package set in
# README.md and with the profile check below.
PACKAGES=(
  glib gtk3 gnome-themes-extra
  desktop-file-utils shared-mime-info
  polkit_gnome xdg-user-dirs xfce4-exo garcon libxfce4ui mousepad parole
  ristretto xfce4-appfinder xfce4-notifyd xfce4-screenshooter xfce4-session
  xfce4-settings xfce4-taskmanager xfce4-terminal xfwm4 xfwm4-themes
  xfce4-panel xfdesktop xfce4-screensaver thunar thunar-volman tumbler
  xfconf linux-pam qt6Packages.sddm
)

# Resource caps.
CPUSET=${CPUSET:-0-5}
CPUQUOTA=${CPUQUOTA:-600%}
MEMCAP=${MEMCAP:-6G}
CAP=${CAP:-1}

log() { printf '\033[1;35m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ -d "$ROOTFS" ] || die "rootfs not found at $ROOTFS"
[ "$(id -u)" -eq 0 ] || command -v sudo >/dev/null || die "need root or sudo to chroot"

asroot() { if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi; }

# nix-env is reached through /nix/var/nix/profiles/default, which is an
# absolute symlink into the image's own /nix/store.  It only resolves inside
# the chroot, so test it there -- checking "$ROOTFS$NIXBIN/nix-env" on the
# host fails on any machine that does not itself have /nix.
asroot chroot "$ROOTFS" test -x "$NIXBIN/nix-env" \
  || die "rootfs is missing the bundled Nix ($NIXBIN/nix-env)"

# --- chroot mount handling -------------------------------------------------
MOUNTS=()
cleanup() {
  local i
  # Unmount in reverse mount order, recursively.  A plain "umount dev" fails
  # with EBUSY because the rbind carries submounts (dev/shm, dev/pts,
  # dev/mqueue, dev/hugepages); if it leaks, the next `git status` sees
  # devtmpfs device nodes instead of the tracked rootfs/dev/null placeholder.
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

# Run a command inside the chroot, resource-capped.
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

# --- fetch nixpkgs ---------------------------------------------------------
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

# --- main ------------------------------------------------------------------
log "TacoLinux desktop build"
log "rootfs:  $ROOTFS"
log "profile: $PROFILE"

fetch_nixpkgs
mount_chroot

# Register the committed bootstrap closure in the Nix DB if it is not there
# yet.  On a fresh clone the DB is present, but be defensive.
if [ ! -s "$ROOTFS/nix/var/nix/db/db.sqlite" ] ||
   [ "$(stat -c%s "$ROOTFS/nix/var/nix/db/db.sqlite" 2>/dev/null || echo 0)" -lt 4096 ]; then
  log "loading bootstrap Nix DB from .reginfo"
  asroot chroot "$ROOTFS" "$NIXBIN/nix-store" --load-db < "$ROOTFS/nix/.reginfo"
fi

log "installing ${#PACKAGES[@]} packages (this downloads ~2 GiB the first time)"
# Building the profile derivation needs a build user.  The rootfs has no
# nixbld users, and we are already root inside a chroot, so build as root.
in_chroot "$NIXBIN/nix-env" -f "$NIXPKGS_IN_CHROOT" -iA "${PACKAGES[@]}" \
  --profile "$PROFILE" --option cores 4 --option max-jobs 2 \
  --option build-users-group '' \
  2> >(grep -v "build-users-group" >&2)

# PAM modules live in the profile; the /etc/pam.d files reference them by
# absolute path.  Fail loudly if the expected layout is not there.  The
# profile is an absolute symlink into /nix/store, so test it inside the
# chroot -- on the host it does not resolve.
if ! asroot chroot "$ROOTFS" test -e "$PROFILE/lib/security/pam_unix.so"; then
  log "warning: pam_unix.so not found in $PROFILE/lib/security"
  log "         (check that linux-pam is in PACKAGES)"
fi

# pam_unix execs /usr/sbin/unix_chkpwd to verify passwords for unprivileged
# callers.  It lives in the linux-pam package, which is only in the desktop
# profile, so expose it at the path PAM hard-codes.  Without this the SDDM
# greeter cannot authenticate anyone: "helper binary execve failed".
asroot chroot "$ROOTFS" ln -sf "$PROFILE/bin/unix_chkpwd" /usr/sbin/unix_chkpwd

# Refresh the portable DB dump so the built image is self-describing.
log "regenerating nix/.reginfo"
asroot chroot "$ROOTFS" "$NIXBIN/nix-store" --dump-db > "$ROOTFS/nix/.reginfo"

log "done: desktop profile is $PROFILE"
