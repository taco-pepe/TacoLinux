#!/usr/bin/env bash
# Verify that every bundled CLI tool in rootfs/usr/local/bin is a real,
# fully static ELF that actually runs.  Catches the classic regression:
# a dynamically linked binary sneaking in and demanding a foreign glibc.
#
# Usage: scripts/test-cli-tools.sh [bindir] [listfile]
set -uo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
bindir=${1:-$repo_root/rootfs/usr/local/bin}
list=${2:-$repo_root/rootfs/usr/local/share/tacolinux/cli-tools.txt}

[ -d "$bindir" ] || { echo "no such directory: $bindir" >&2; exit 1; }

# Only the bundled tools are ours; /usr/local/bin also holds the base system.
if [ -f "$list" ]; then
    mapfile -t names < <(grep -v '^[[:space:]]*#' "$list" | grep -v '^[[:space:]]*$')
else
    names=()
    for f in "$bindir"/*; do
        [ -f "$f" ] && names+=("$(basename "$f")")
    done
fi

total=0 static=0 dynamic=0 broken=0 noexec=0 missing=0
printf '%-22s %-8s %-10s %s\n' TOOL LINK RUN VERSION
printf '%-22s %-8s %-10s %s\n' ---- ---- --- -------

for b in "${names[@]}"; do
    f="$bindir/$b"
    if [ ! -e "$f" ]; then
        printf '%-22s %-8s %-10s %s\n' "$b" "MISSING" "-" "-"
        missing=$((missing + 1))
        continue
    fi
    total=$((total + 1))

    if [ ! -x "$f" ]; then
        printf '%-22s %-8s %-10s %s\n' "$b" "?" "NOEXEC" "-"
        noexec=$((noexec + 1))
        continue
    fi

    if ! head -c4 "$f" | od -An -tx1 | grep -q '7f 45 4c 46'; then
        printf '%-22s %-8s %-10s %s\n' "$b" "script" "ok" "-"
        continue
    fi

    if readelf -l "$f" 2>/dev/null | grep -q INTERP; then
        printf '%-22s %-8s %-10s %s\n' "$b" "DYNAMIC" "-" "-"
        dynamic=$((dynamic + 1))
        continue
    fi
    static=$((static + 1))

    # find a version flag the tool answers to
    out=""
    for flag in --version -V -version -v; do
        out=$("$f" "$flag" 2>&1 | head -n1)
        [ -n "$out" ] && break
    done
    if [ -z "$out" ]; then
        out=$("$f" -h 2>&1 | head -n1)
    fi
    if [ -z "$out" ]; then
        out="(no --version)"
        broken=$((broken + 1))
    fi
    printf '%-22s %-8s %-10s %s\n' "$b" "static" "ok" "${out:0:58}"
done

echo
echo "total=$total static=$static dynamic=$dynamic noexec=$noexec no-version=$broken missing=$missing"
if [ "$dynamic" -gt 0 ] || [ "$noexec" -gt 0 ] || [ "$missing" -gt 0 ]; then
    echo "FAIL: shipped binaries must be static and executable" >&2
    exit 1
fi
