# Taco session kicker: rise Xorg + dwm on the primary vt,
# mirroring all output to the serial console for diagnostics.
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    echo "[taco] starting X session" > /dev/ttyS0
    ls -la /usr/local/sbin/xlaunch > /dev/ttyS0
    id > /dev/ttyS0
    # Xorg runs as root via the setuid xlaunch helper (no PAM/logind seat
    # for non-root here); window manager / terminals stay as taco.
    /usr/local/sbin/xlaunch >/tmp/xl.out 2>&1 &
    xp=$!
    export DISPLAY=:0
    got=0
    for i in $(seq 1 30); do
        [ -S /tmp/.X11-unix/X0 ] && { echo "[taco] X socket up (try $i)" > /dev/ttyS0; got=1; break; }
        sleep 1
    done
    if [ "$got" = 1 ]; then
        echo "[taco] X is up; launching installer TUI + dwm" > /dev/ttyS0
        xterm -bg black -fg '#e0e0e0' -fa "DejaVu Sans Mono" -fs 12 -tn xterm \
              -T "TacoLinux Installer" -e /usr/local/bin/taco-installer &
        exec dwm
    else
        echo "[taco] X socket never appeared; xlaunch pid=$xp" > /dev/ttyS0
        if kill -0 "$xp" 2>/dev/null; then
            echo "[taco] xlaunch still running" > /dev/ttyS0
        else
            echo "[taco] xlaunch exited rc=$?" > /dev/ttyS0
        fi
        cat /tmp/xl.out > /dev/ttyS0
        ls -la /tmp /var/log/Xorg.0.log > /dev/ttyS0 2>&1
        [ -f /var/log/Xorg.0.log ] && tail -80 /var/log/Xorg.0.log > /dev/ttyS0
        sleep 5
    fi
    exit
elif [ -n "$DISPLAY" ]; then
    # inside the desktop: show a splash once per login shell
    command -v fastfetch >/dev/null 2>&1 && fastfetch 2>/dev/null
fi
