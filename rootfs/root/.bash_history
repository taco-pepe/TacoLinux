sudo cp /mnt/storage/tacolinux/rootfs-systemd/root/.config/fastfetch/config.jsonc   /mnt/storage/tacolinux/rootfs-systemd/home/taco/.config/fastfetch/config.jsonc
sudo chown -R 1000:1000   /mnt/storage/tacolinux/rootfs-systemd/home/taco/.config
exit
fastfetch
grep -RFnE 'kernel/random/(uuid|boot_id)'   /mnt/storage/tacolinux/rootfs-systemd/home/taco   /mnt/storage/tacolinux/rootfs-systemd/etc   /mnt/storage/tacolinux/rootfs-systemd/root   2>/dev/null
exit
ldd --version
/lib/x86_64-linux-gnu/libc.so.6
ls
ls /lib/
ls lib64/x86_64
ls lib64/
exit
fastfetch
exit
cat >> /etc/profile <<'EOF'

# TacoLinux prompt
if [ -n "$BASH_VERSION" ] && [[ $- == *i* ]]; then
    if (( EUID == 0 )); then
        PS1='\[\e[1;38;5;208m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\] # '
    else
        PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\] \$ '
    fi
fi
EOF

source /etc/profile
WOW
exit
