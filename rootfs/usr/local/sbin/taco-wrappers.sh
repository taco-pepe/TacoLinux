#!/bin/sh
# Install setuid helpers at boot.  See /etc/tmpfiles.d/taco-wrappers.conf.
#
# unix_chkpwd: Nix's pam_unix shells out to /run/wrappers/bin/unix_chkpwd for
# unprivileged password checks (SDDM greeter, passwd).  The profile entry is a
# symlink into /nix/store, so resolve it before copying -- a copied symlink
# points at a non-setuid file and auth fails.
#
# su: git cannot store the setuid bit, so the committed BusyBox su is 0755 on
# a fresh checkout and after rsync.  build-vm-image.sh also fixes it; this
# covers booting a rootfs whose mode was lost.  passwd is setuid for the same
# reason: pam_unix needs to read /etc/shadow to verify the current password.
set -eu

profile=/nix/var/nix/profiles/desktop/bin/unix_chkpwd
if [ -e "$profile" ]; then
    src=$(readlink -f "$profile")
    mkdir -p /run/wrappers/bin
    install -m 4755 -o root -g root "$src" /run/wrappers/bin/unix_chkpwd
fi

if [ -e /usr/local/bin/su ]; then
    chmod 4755 /usr/local/bin/su
fi

if [ -e /usr/local/bin/passwd ]; then
    chmod 4755 /usr/local/bin/passwd
fi
