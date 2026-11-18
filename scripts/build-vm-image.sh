#!/usr/bin/env bash
#
# build-vm-image.sh -- turn rootfs/ into a bootable disk image.
#
# Layout (GPT):
#   p1  BIOS boot   2 MiB, raw -- GRUB embeds core.img here (no filesystem!)
#   p2  root        ext4, everything else -- contains /boot with kernel/initramfs
#
# The rootfs is rsynced onto p2.  GRUB is installed to the *disk* with
# --boot-directory pointing at <root>/boot, so modules and grub.cfg end up in
# the root filesystem and core.img lands in p1.
#
# Outputs (in $OUTDIR):
#   tacolinux-<version>-x86_64.img.zst   raw image, for `zstd -d | dd`
#   tacolinux-<version>-x86_64.qcow2     ready to run in QEMU
#   SHA256SUMS
#
# Requires root (loop devices + mount).  In CI, run it under sudo.
#
# Env:
#   ROOTFS      source tree                     (default: <repo>/rootfs)
#   OUTDIR      output directory                (default: <repo>/dist)
#   IMG_SIZE    raw disk size, e.g. 8G or auto  (default: auto)
#   NAME        image basename                  (default: tacolinux)
#   VERSION     version string                  (default: git describe)
#   QCOW2       1 to also make a qcow2          (default: 1)
#   COMPRESS    zstd | xz | gzip | none         (default: zstd)
#   KEEP_RAW    1 to keep the uncompressed raw  (default: 0)
#
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ROOTFS=${ROOTFS:-$REPO_ROOT/rootfs}
OUTDIR=${OUTDIR:-$REPO_ROOT/dist}
IMG_SIZE=${IMG_SIZE:-auto}
NAME=${NAME:-tacolinux}
VERSION=${VERSION:-$(git -C "$REPO_ROOT" describe --tags --always --dirty 2>/dev/null || echo dev)}
QCOW2=${QCOW2:-1}
COMPRESS=${COMPRESS:-zstd}
KEEP_RAW=${KEEP_RAW:-0}
BIOS_BOOT_MIB=2
MOUNT=${MOUNT:-/mnt/tacolinux-image}

log() { printf '\033[1;35m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "must run as root (loop devices + mount)"
[ -d "$ROOTFS" ] || die "rootfs not found at $ROOTFS"
[ -f "$REPO_ROOT/bootstrap/bzImage" ] || die "missing bootstrap/bzImage"
[ -f "$REPO_ROOT/bootstrap/initramfs.img" ] || die "missing bootstrap/initramfs.img"
for cmd in sfdisk losetup mkfs.ext4 mount rsync blkid qemu-img; do
  command -v "$cmd" >/dev/null || die "missing required command: $cmd"
done
GRUB_INSTALL=$(command -v grub-install || command -v grub2-install) \
  || die "missing required command: grub-install"

# --- size the disk ---------------------------------------------------------
if [ "$IMG_SIZE" = auto ]; then
  content=$(du -sB1 --apparent-size "$ROOTFS" | cut -f1)
  # 10% slack for filesystem overhead + a few hundred MiB to breathe.
  IMG_SIZE=$(( (content * 11 / 10) + 384 * 1024 * 1024 ))
  IMG_SIZE=$(( (IMG_SIZE + 1024 * 1024 - 1) / (1024 * 1024) ))M
  log "auto-sized image: $IMG_SIZE for $((content / 1024 / 1024)) MiB of rootfs"
fi

mkdir -p "$OUTDIR"
WORK=$(mktemp -d "$OUTDIR/.build.XXXXXX")
IMG="$WORK/$NAME.img"
RAW="$OUTDIR/$NAME-$VERSION-x86_64.img"
QCOW="$OUTDIR/$NAME-$VERSION-x86_64.qcow2"
LOOP=""
MOUNTED=0

cleanup() {
  set +e
  [ "$MOUNTED" = 1 ] && umount "$MOUNT"
  [ -n "$LOOP" ] && losetup -d "$LOOP"
  rm -rf "$WORK"
}
trap cleanup EXIT

# --- create the blank disk -------------------------------------------------
log "creating $IMG_SIZE sparse image"
truncate -s "$IMG_SIZE" "$IMG"

log "partitioning (GPT: p1 BIOS boot, p2 root)"
sfdisk --quiet "$IMG" <<EOF
label: gpt
start=2048, size=$((BIOS_BOOT_MIB * 2048)), type=21686148-6449-6E6F-744E-656564454649, name="BIOS boot"
start=$((2048 + BIOS_BOOT_MIB * 2048)), type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="root"
EOF

LOOP=$(losetup --find --show --partscan "$IMG")
command -v udevadm >/dev/null && udevadm settle || true
ROOT_PART="${LOOP}p2"
[ -b "$ROOT_PART" ] || die "partition device $ROOT_PART did not appear"

log "formatting root filesystem"
mkfs.ext4 -q -F -L TacoLinux "$ROOT_PART"

log "copying rootfs (this takes a while)"
mkdir -p "$MOUNT"
mount "$ROOT_PART" "$MOUNT"
MOUNTED=1
# /dev, /proc, /sys, /run, /host and /nixpkgs are runtime or build-time mount
# points: the kernel mounts the first four at boot, and the last two are where
# the build scripts bind-mount things while chrooting.  Whatever a local build
# happened to leave there must not end up in the published image.  rsync still
# creates the (empty) directories.
rsync -aHAXS --numeric-ids \
  --exclude '/dev/*' --exclude '/proc/*' --exclude '/sys/*' --exclude '/run/*' \
  --exclude '/host/*' --exclude '/nixpkgs/*' \
  "$ROOTFS/" "$MOUNT/"
mkdir -p "$MOUNT/etc" "$MOUNT/boot"

# rsync -a preserves ownership, and this tree is checked out by an ordinary
# user, so without this the image's / is owned by uid 1000.  systemd refuses
# to touch paths under a non-root-owned /: systemd-tmpfiles logs "Detected
# unsafe path transition / (owned by taco)" and skips its rules, so
# /run/wrappers never appears and the SDDM greeter cannot authenticate.
# Own the whole tree by root, then give back the few paths that belong to a
# service account.  The uids are read from the image's own /etc/passwd so they
# cannot drift out of sync with it.
log "fixing ownership"
chown -R root:root "$MOUNT"
chown_image_owner() {
  local uid gid
  uid=$(awk -F: -v u="$2" '$1 == u { print $3 }' "$MOUNT/etc/passwd")
  gid=$(awk -F: -v u="$2" '$1 == u { print $4 }' "$MOUNT/etc/passwd")
  [ -n "$uid" ] || return 0
  chown -R "$uid:$gid" "$1" 2>/dev/null || true
}
chown_image_owner "$MOUNT/home/taco" taco
chown_image_owner "$MOUNT/var/lib/sddm" sddm

# systemd runs these paths directly.  rsync preserves modes, and a launcher
# that lost its +x bit is not a build error -- it is a 203/EXEC at boot, after
# the image has already been published.  Fail here instead.
missing_x=$(find "$MOUNT/usr/local/bin" "$MOUNT/usr/local/sbin" \
              -type f ! -perm -u+x -print -quit 2>/dev/null || true)
[ -z "$missing_x" ] || die "not executable: ${missing_x#"$MOUNT"} (systemd would fail with 203/EXEC)"

# --- kernel, initramfs, fstab, grub.cfg ------------------------------------
log "installing kernel and initramfs into /boot"
install -D -m644 "$REPO_ROOT/bootstrap/bzImage" "$MOUNT/boot/bzImage"
install -D -m644 "$REPO_ROOT/bootstrap/initramfs.img" "$MOUNT/boot/initramfs.img"

ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
[ -n "$ROOT_UUID" ] || die "could not read root filesystem UUID"

log "writing /etc/fstab"
cat > "$MOUNT/etc/fstab" <<EOF
# <file system> <mount point> <type> <options> <dump> <pass>
UUID=$ROOT_UUID  /  ext4  defaults  0  1
EOF
echo "tacolinux" > "$MOUNT/etc/hostname"

# --- normalize permissions -------------------------------------------------
# rsync -p preserves whatever modes the source tree happens to have.  A
# passwd/group that is not world-readable makes every NSS lookup fail, which
# shows up as "Failed to start D-Bus System Message Bus" (dbus-daemon runs as
# messagebus and cannot resolve its own uid).  Normalize the critical files so
# a stray local chmod can never produce an unbootable image.
log "normalizing /etc permissions"
chmod 644 "$MOUNT/etc/passwd" "$MOUNT/etc/group" "$MOUNT/etc/hostname" \
          "$MOUNT/etc/nsswitch.conf" "$MOUNT/etc/fstab" 2>/dev/null || true
chmod 640 "$MOUNT/etc/shadow" "$MOUNT/etc/gshadow" 2>/dev/null || true
chmod 1777 "$MOUNT/tmp" "$MOUNT/var/tmp" 2>/dev/null || true
chmod 700 "$MOUNT/root" 2>/dev/null || true
# sshd refuses to start unless its chroot directory is root-owned and not
# group/world-writable ("/var/empty must be owned by root").
mkdir -p "$MOUNT/var/empty"
chown root:root "$MOUNT/var/empty" 2>/dev/null || true
chmod 755 "$MOUNT/var/empty" 2>/dev/null || true

# --- restore setuid helpers ------------------------------------------------
# Two independent things lose the setuid bit, so it must be set explicitly
# here.  git only records the executable bit, so a committed sudo is plain
# 0755 on a fresh clone; and chown() clears setuid/setgid on Linux even when
# root does the chown() (which we do above).  Without this the image ships a
# sudo that cannot elevate, a broken ssh-keysign, and a broken xlaunch.
log "restoring setuid helpers"
for helper in "4755 usr/bin/sudo" "4755 usr/local/sbin/xlaunch" \
              "4711 usr/libexec/ssh-keysign"; do
  mode=${helper%% *}; path=${helper#* }
  [ -e "$MOUNT/$path" ] || die "missing setuid helper: /$path"
  chmod "$mode" "$MOUNT/$path"
done

# --- strip machine-specific state -----------------------------------------
log "cleaning machine identity"
if [ -f "$MOUNT/etc/machine-id" ]; then
  : > "$MOUNT/etc/machine-id"
  chmod 444 "$MOUNT/etc/machine-id"
fi
rm -f "$MOUNT/var/lib/dbus/machine-id" \
      "$MOUNT/var/lib/systemd/random-seed" \
      "$MOUNT/etc/ssh/ssh_host_"*
rm -rf "$MOUNT/var/log/journal"/*
find "$MOUNT/var/log" -type f -size +1M -delete 2>/dev/null || true

# --- install GRUB ----------------------------------------------------------
log "installing GRUB (i386-pc) to $LOOP"
"$GRUB_INSTALL" \
  --target=i386-pc \
  --boot-directory="$MOUNT/boot" \
  --no-floppy \
  --recheck \
  "$LOOP"

# The module directory is /boot/grub on Debian/Ubuntu and /boot/grub2 on
# Fedora.  Write grub.cfg next to the modules GRUB actually installed.
GRUB_DIR=$(find "$MOUNT/boot" -mindepth 1 -maxdepth 1 -type d \
             -name 'grub*' -exec test -d '{}/i386-pc' \; -print -quit)
[ -n "$GRUB_DIR" ] || die "could not locate the installed GRUB directory"

log "writing $GRUB_DIR/grub.cfg"
cat > "$GRUB_DIR/grub.cfg" <<EOF
set timeout=3
set default=0

menuentry "TacoLinux (release)" {
    echo "we in"
    echo "bootin your system :D"
    search --no-floppy --fs-uuid --set=root $ROOT_UUID
    linux /boot/bzImage root=UUID=$ROOT_UUID rw rootfstype=ext4 console=tty0 console=ttyS0,115200
    initrd /boot/initramfs.img
}
EOF

sync
umount "$MOUNT"
MOUNTED=0
losetup -d "$LOOP"
LOOP=""

# --- convert + compress ----------------------------------------------------
log "moving raw image to $RAW"
mv "$IMG" "$RAW"
cd "$OUTDIR"

if [ "$QCOW2" = 1 ]; then
  log "converting to qcow2"
  qemu-img convert -f raw -O qcow2 -p "$RAW" "$QCOW"
  qemu-img info "$QCOW"
fi

case "$COMPRESS" in
  zstd)
    log "compressing raw image with zstd"
    if ! zstd -T0 -19 --long=27 -q -f "$RAW" -o "$RAW.zst"; then
      log "level 19 failed, retrying with level 12"
      zstd -T0 -12 -q -f "$RAW" -o "$RAW.zst"
    fi
    ;;
  xz)   log "compressing raw image with xz -9e (maximum)"; xz -T0 -9e -f -k "$RAW" ;;
  gzip) log "compressing raw image with gzip"; gzip -9 -f -k "$RAW" ;;
  none) ;;
  *) die "unknown COMPRESS=$COMPRESS (zstd|xz|gzip|none)" ;;
esac

if [ "$KEEP_RAW" != 1 ]; then
  rm -f "$RAW"
fi

# --- checksums -------------------------------------------------------------
log "writing SHA256SUMS"
( cd "$OUTDIR" && sha256sum "$NAME-$VERSION"-x86_64.* > SHA256SUMS )

# When run via sudo on a dev machine, leave the results owned by the caller.
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
  chown "$SUDO_USER:" "$OUTDIR"/* 2>/dev/null || true
  chown "$SUDO_USER:" "$OUTDIR" 2>/dev/null || true
fi

log "done:"
ls -lh "$OUTDIR" | sed 's/^/    /'
