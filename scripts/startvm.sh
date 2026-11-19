#!/usr/bin/env bash
set -euo pipefail

# Boot a TacoLinux disk image in QEMU/KVM.
# Usage: startvm.sh <image> [overlay.qcow2]
#
# If no overlay is given, a qcow2 overlay is created next to the image/cache
# so the base image is never modified.

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <image> [overlay.qcow2]" >&2
  exit 1
fi

IMG="$(realpath "$1")"
if [[ ! -f "$IMG" ]]; then
  echo "Image not found: $IMG" >&2
  exit 1
fi

if [[ $# -ge 2 ]]; then
  OVL="$(realpath -m "$2")"
else
  cache_dir="${XDG_CACHE_HOME:-$PWD/.cache}"
  mkdir -p "$cache_dir"
  base="$(basename "$IMG")"
  OVL="$cache_dir/${base%.img}.overlay.qcow2"
fi

if [[ ! -f "$OVL" ]]; then
  echo "Creating overlay: $OVL"
  qemu-img create -f qcow2 -F raw -b "$IMG" "$OVL" >/dev/null
else
  echo "Using existing overlay: $OVL"
fi

mkdir -p "$(dirname "$OVL")"
SERIAL_LOG="${OVL%.qcow2}.serial.log"
QEMU_LOG="${OVL%.qcow2}.qemu.log"
MON_SOCK="${OVL%.qcow2}.monitor.sock"

: "${MEM:=1536}"
: "${SMP:=2}"
: "${DISPLAY_BACKEND:=gtk}"
: "${SSH_PORT:=2222}"

echo "Booting: $IMG"
echo "Overlay: $OVL"
echo "Serial log: $SERIAL_LOG"
echo "SSH: ssh -p $SSH_PORT taco@localhost"

exec qemu-system-x86_64 -enable-kvm -cpu host -m "$MEM" -smp "$SMP" \
  -drive "file=$OVL,format=qcow2,if=virtio" \
  -vga std -display "$DISPLAY_BACKEND" \
  -nic "user,model=virtio-net-pci,hostfwd=tcp::${SSH_PORT}-:22" \
  -device qemu-xhci,id=xhci -device usb-tablet,bus=xhci.0 \
  -monitor "unix:$MON_SOCK,server=on,wait=off" \
  -serial "file:$SERIAL_LOG" \
  -name "TacoLinux" \
  >"$QEMU_LOG" 2>&1
