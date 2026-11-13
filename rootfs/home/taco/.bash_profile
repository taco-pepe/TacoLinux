# TacoLinux ~/.bash_profile
# Normal login shell startup. Graphical sessions are started by SDDM
# (see /etc/sddm.conf); nothing here should auto-launch X.

# Greet the user with a splash inside a graphical terminal.
if [ -n "$DISPLAY" ]; then
    command -v fastfetch >/dev/null 2>&1 && fastfetch 2>/dev/null
fi
