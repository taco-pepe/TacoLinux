#!/usr/bin/env bash
# Inner build script: runs inside an Alpine container (see scripts/build-cli-tools.sh).
# Inputs:  /src  = vendored sources (read-only)
#          /out  = build output (bin/ + sbin/ + logs + report)
# Only fully static (no PT_INTERP) ELF binaries are harvested, so they run on
# TacoLinux regardless of its glibc/Nix layout.
set -u

PREFIX=/out
J=${JOBS:-4}
export CFLAGS="-O2 -pipe -fno-plt -std=gnu17"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-static"
export PKG_CONFIG="pkg-config --static"

# libtool strips a plain "-static" from compiler invocations, so wrap the
# compiler: every call links statically, even through libtool.  Shared-library
# builds are passed through unchanged.
REAL_CC="$(command -v gcc)"
mkdir -p /work/.cc
cat > /work/.cc/gcc <<EOF
#!/bin/sh
case " \$* " in
    *" -shared "*) exec $REAL_CC "\$@" ;;
esac
exec $REAL_CC -static "\$@"
EOF
chmod +x /work/.cc/gcc
export PATH="/work/.cc:$PATH"

LOG=/out/logs
mkdir -p "$LOG" /work "$PREFIX"/bin "$PREFIX"/sbin

say() { printf '%s\n' "$*"; }

apk_install() {
    [ "${SKIP_APK:-0}" = "1" ] && return 0
    # one index refresh, then one atomic add; fall back to per-package installs
    # only if the combined set fails (a single bad name would fail it all)
    apk update >/dev/null 2>&1 || true
    all="bash build-base linux-headers autoconf automake libtool pkgconf \
         gettext-dev ncurses-dev ncurses-static zlib-dev zlib-static \
         openssl-dev openssl-libs-static libevent-dev libevent-static \
         libpcap-dev pcre2-dev pcre2-static oniguruma-dev readline-dev \
         readline-static elfutils-dev libcap-dev bsd-compat-headers lz4-dev"
    if ! apk add --no-progress $all >/dev/null 2>&1; then
        for p in $all; do
            apk add --no-progress "$p" >/dev/null 2>&1 || say "warn: no package $p"
        done
    fi
}

# some upstream archives have no generated configure script
prep_build() {
    if [ ! -x ./configure ] && [ -f configure.ac ]; then
        autoreconf -fi
    fi
}

# copy a pristine source tree into the build area and enter it
in_src() {
    local d="$1"
    rm -rf "/work/$d"
    cp -a "/src/$d" "/work/$d"
    cd "/work/$d"
}

# ---------------------------------------------------------------- recipes ---
b_nano()   { in_src nano;   ./configure --prefix=$PREFIX --disable-nls --enable-utf8; make -j"$J"; make install; }
b_less()   { in_src less;   ./configure --prefix=$PREFIX --disable-nls; make -j"$J"; make install; }
b_tree()   { in_src tree;   make -j"$J" CC=gcc LDFLAGS=-static; install -m755 tree $PREFIX/bin/; }
b_jq()     { in_src jq;     ./configure --prefix=$PREFIX --disable-docs --enable-all-static --with-oniguruma=builtin; make -j"$J"; make install; }
b_ncdu()   { in_src ncdu;   ./configure --prefix=$PREFIX --with-ncursesw --disable-nls; make -j"$J"; make install; }
b_patch()  { in_src patch;  ./configure --prefix=$PREFIX --disable-nls; make -j"$J"; make install; }

b_socat()  {
    in_src socat
    if ! { ./configure --prefix=$PREFIX --disable-nls && make -j"$J" && make install; }; then
        say "socat: retrying without OpenSSL"
        make distclean >/dev/null 2>&1 || true
        ./configure --prefix=$PREFIX --disable-nls --disable-openssl
        make -j"$J"; make install
    fi
}

b_lsof()   { in_src lsof; ./configure --prefix=$PREFIX --disable-shared; make -j"$J"; make install; }

b_wget()   {
    in_src wget
    ./configure --prefix=$PREFIX --disable-nls --with-ssl=openssl \
        --without-libpsl --without-libidn2 --without-metalink
    if ! { make -j"$J" && make install; }; then
        say "wget: OpenSSL static link failed, rebuilding HTTP-only"
        make distclean >/dev/null 2>&1 || true
        ./configure --prefix=$PREFIX --disable-nls --without-ssl --without-zlib
        make -j"$J"; make install
    fi
}

b_tmux()   { in_src tmux; ./configure --prefix=$PREFIX --disable-utf8proc CFLAGS="$CFLAGS" LDFLAGS=-static; make -j"$J"; make install; }
b_file()   { in_src file; prep_build; ./configure --prefix=$PREFIX --disable-nls --disable-shared; make -j"$J" LDFLAGS="-static -all-static"; make install; }
b_strace() {
    in_src strace
    # Alpine's linux-headers renamed the mnt_id_req spare field to mnt_ns_id
    sed -i 's/spare/mnt_ns_id/g' src/listmount.c src/statmount.c src/print_fields.h
    ./configure --prefix=$PREFIX --disable-mpers CPPFLAGS="-DINPUT_PROP_HAPTIC_TOUCHPAD=0x08"
    make -j"$J"
    make install
}
b_bc()     { in_src bc;     ./configure --prefix=$PREFIX --without-readline --disable-nls; make -j"$J"; make install-exec; }
b_units()  { in_src units;  ./configure --prefix=$PREFIX LIBS="-ltinfo"; make -j"$J"; make install; }

b_screen() {
    in_src screen
    ./configure --prefix=$PREFIX --disable-pam --disable-nls --enable-colors256 \
        --disable-utempter --with-socket-dir=/run/screens
    make -j"$J"; make install
}

b_mg() {
    in_src mg
    # mg ships a BSD makefile (mmake), so compile the sources directly.
    # Alpine has no <util.h>; provide the two helpers mg needs from it.
    printf '#include <pty.h>\n#include <utmp.h>\n' > util.h
    srcs=$(ls *.c | tr '\n' ' ')
    gcc -O2 -std=gnu17 -DREGEX -DHAVE_PTY_H=1 -DHAVE_UTIL_H=0 -I. \
        -include bsd/stdlib.h \
        $(pkg-config --cflags-only-I ncurses) \
        -o mg $srcs $(pkg-config --libs ncurses) -lutil -lbsd
    install -m755 mg $PREFIX/bin/
}
b_entr()       { in_src entr;   ./configure; make -j"$J" CC="gcc -static"; make install PREFIX=$PREFIX; }
b_fdupes()     { in_src fdupes; ./configure --prefix=$PREFIX --without-sqlite; make -j"$J"; make install; }
b_dos2unix()   { in_src dos2unix; make -j"$J" CC=gcc ENABLE_NLS=; make install prefix=$PREFIX; }

# libpcap first: tcpdump/iftop/mtr link against the static lib we just built
b_libpcap()    { in_src libpcap; ./configure --prefix=$PREFIX --disable-shared --enable-static; make -j"$J"; make install; }

b_tcpdump() {
    in_src tcpdump
    prep_build
    ./configure --prefix=$PREFIX --disable-nls --disable-smi --disable-crypto \
        CPPFLAGS="-I$PREFIX/include" LDFLAGS="-static -L$PREFIX/lib"
    make -j"$J"; make install
}

b_mtr()    { in_src mtr;    prep_build; ./configure --prefix=$PREFIX --without-jansson --disable-nls; make -j"$J"; make install; }
b_iftop()  { in_src iftop;  ./configure --prefix=$PREFIX CFLAGS="$CFLAGS -fcommon" CPPFLAGS="-I$PREFIX/include" LDFLAGS="-static -L$PREFIX/lib"; make -j"$J"; make install; }

b_netcat_openbsd() {
    in_src netcat
    if [ -f Makefile ]; then
        make -j"$J" CFLAGS="$CFLAGS -D_GNU_SOURCE" || true
    fi
    if [ ! -x nc ]; then
        srcs="netcat.c"
        for extra in atomicio.c socks.c; do [ -f "$extra" ] && srcs="$srcs $extra"; done
        gcc -O2 -static -std=gnu17 -D_GNU_SOURCE -o nc $srcs
    fi
    install -m755 nc $PREFIX/bin/
}

b_sshpass()   { in_src sshpass; ./configure --prefix=$PREFIX; make -j"$J"; make install; }

b_net_tools() {
    in_src net-tools
    make -j"$J" CC=gcc LDFLAGS=-static
    make install BASEDIR=$PREFIX
}

b_psmisc()  { in_src psmisc;  ./configure --prefix=$PREFIX --disable-nls; make -j"$J"; make install; }

b_pciutils() {
    in_src pciutils
    make -j"$J" SHARED=no PREFIX=$PREFIX OPT="-O2 -static" ZLIB=no
    make install PREFIX=$PREFIX SHARED=no
}

b_ethtool() { in_src ethtool; prep_build; PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" ./configure --prefix=$PREFIX CPPFLAGS="-I$PREFIX/include" LDFLAGS="-static -L$PREFIX/lib"; make -j"$J"; make install; }
b_ltrace()  { in_src ltrace;  ./configure --prefix=$PREFIX --disable-werror CFLAGS="$CFLAGS -DREG_NOERROR=0"; make -j"$J" LIBS="-lelf"; make install; }
b_pv()      { in_src pv;      ./configure --prefix=$PREFIX --disable-nls; make -j"$J"; make install; }

b_moreutils() {
    in_src moreutils
    make -j"$J" CC="gcc -static" || true
    for f in sponge ts pee ifne isutf8 combine lckdo mispipe parallel; do
        [ -x "$f" ] && install -m755 "$f" $PREFIX/bin/ || true
    done
}

b_zstd() {
    in_src zstd
    make -j"$J" -C lib libzstd.a
    make -j"$J" -C programs zstd LDFLAGS="-static" LDLIBS="-pthread -lz"
    install -m755 programs/zstd $PREFIX/bin/
}

b_hdparm()  { in_src hdparm; make -j"$J" CC="gcc -static"; install -m755 hdparm $PREFIX/sbin/; }
b_dialog()  { in_src dialog; ./configure --prefix=$PREFIX --disable-nls --with-ncursesw; make -j"$J"; make install; }
b_jo()      { in_src jo;     prep_build; ./configure --prefix=$PREFIX; make -j"$J"; make install; }

b_lz4() {
    in_src lz4
    make -j"$J" -C lib liblz4.a
    make -j"$J" -C programs lz4 LDFLAGS=-static
    install -m755 programs/lz4 $PREFIX/bin/
}

b_unzip() {
    in_src unzip
    # unzip 6.0 declares gmtime()/localtime() K&R-style, which modern libc
    # headers reject; drop those declarations and use <time.h>
    sed -i '/struct tm \*gmtime(), \*localtime();/d' unix/unxcfg.h
    make -f unix/Makefile CC="gcc" CFLAGS="-O2 -std=gnu17 -I. -DUNIX -DLINUX" linux_noasm
    install -m755 unzip $PREFIX/bin/
}

b_libmnl() { in_src libmnl; ./configure --prefix=$PREFIX --disable-shared --enable-static; make -j"$J"; make install; }
b_bzip2()     { in_src bzip2; make -j"$J" CC=gcc LDFLAGS=-static; install -m755 bzip2 $PREFIX/bin/; }
b_procps()    { in_src procps; ./configure --prefix=$PREFIX --disable-nls --without-systemd --disable-shared; make -j"$J"; make install; }

# ------------------------------------------------------------------- main ---
say "== installing build packages =="
apk_install
say "== gcc: $(gcc --version | head -1) =="

names=$(awk -F'\t' '!/^#/ && NF>=5 {print $1}' /build/apps.tsv)

report=/out/BUILD-REPORT.txt
: > "$report"
ok=0; fail=0
for name in $names; do
    recipe=$(printf '%s' "$name" | tr '-' '_')
    if [ ! -d "/src/$(awk -F'\t' -v n="$name" '$1==n{print $3}' /build/apps.tsv)" ]; then
        say "MISSING SOURCE: $name"
        printf 'MISSING  %s\n' "$name" >> "$report"
        continue
    fi
    if ! declare -F "b_$recipe" >/dev/null; then
        say "NO RECIPE: $name"
        printf 'NORECIPE %s\n' "$name" >> "$report"
        continue
    fi
    say "== build $name =="
    if ( set -e; b_"$recipe" ) >"$LOG/$name.log" 2>&1; then
        say "   OK  $name"
        printf 'OK       %s\n' "$name" >> "$report"
        ok=$((ok + 1))
    else
        say "   FAIL $name (see logs/$name.log)"
        printf 'FAIL     %s\n' "$name" >> "$report"
        fail=$((fail + 1))
    fi
done

# --------------------------------------------------------------- harvest ---
mkdir -p /out/static/bin
harvested=/out/BUILT-TOOLS.txt
: > "$harvested"
declare -A seen=()

for dir in "$PREFIX"/bin "$PREFIX"/sbin "$PREFIX"/usr/bin "$PREFIX"/usr/sbin; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*; do
        [ -f "$f" ] || continue
        b=$(basename "$f")
        [ -n "${seen[$b]:-}" ] && continue
        # only real static ELF executables may ship
        head -c4 "$f" | od -An -tx1 | grep -q '7f 45 4c 46' || continue
        if readelf -l "$f" 2>/dev/null | grep -q 'INTERP'; then
            printf 'DROP-DYNAMIC %s\n' "$b" >> "$report"
            rm -f "$f"
            continue
        fi
        install -m755 "$f" /out/static/bin/"$b"
        seen[$b]=1
        printf '%s\n' "$b" >> "$harvested"
    done
done

printf '\nbuilt-ok=%s built-fail=%s harvested=%s\n' "$ok" "$fail" "$(wc -l < "$harvested")" >> "$report"
cat "$report"
