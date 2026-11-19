# TacoLinux ~/.bash_profile
# Normal login shell startup. Graphical sessions are started by SDDM
# (see /etc/sddm.conf); nothing here should auto-launch X.

# Greet the user with a splash inside a graphical terminal.  hyfetch owns
# the logo: on the first run it opens its own setup wizard so you can pick
# your flag.  Re-run `hyfetch -c` any time to change it.  --ascii-file keeps
# the TacoLinux wordmark even after the wizard has saved a different distro.
if [ -n "$DISPLAY" ]; then
    if command -v hyfetch >/dev/null 2>&1; then
        hyfetch --ascii-file=/etc/tacolinux/hyfetch.ascii 2>/dev/null
    elif command -v fastfetch >/dev/null 2>&1; then
        fastfetch 2>/dev/null
    fi
fi
