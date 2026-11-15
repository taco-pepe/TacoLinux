#!/bin/bash
# make tacolinux's initramfs.
# you can use this to customize the initramfs before install.

cd initramfs_rootfs
find . -print0 | cpio --null -ov --format=newc >../initramfs.img
