#!/usr/bin/env bash
# Vendor hyfetch's prebuilt static Rust binary.
#
# hyfetch 2.x is Rust, and this image deliberately does not carry a Rust
# toolchain.  Upstream publishes a musllinux wheel containing a fully static
# binary (no PT_INTERP), which is exactly what TacoLinux needs.  Only this
# tool is prebuilt: everything else under rootfs/usr/local/bin is compiled
# from sources/ by build-cli-tools.sh.
#
# The checksums below pin both the wheel we take the binary from and the
# upstream source tarball kept alongside it.
#
# Usage: scripts/vendor-hyfetch.sh
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
version=2.1.1
base="https://github.com/hykilpikonna/hyfetch/releases/download/$version"

wheel="hyfetch-$version-py3-none-musllinux_1_1_x86_64.whl"
wheel_sha='d74bb00dedbd901b44e22d015ad79f3c5ce6cada618ec0f2fd63bb8de0395117'
source_tar="hyfetch-$version.tar.gz"
source_sha='3dbc5165eeb1790ff9abbc257f834ff9cc6b0f6edd57ea10fcdd2a691710bc20'

dl="$repo_root/.cache/downloads"
dest="$repo_root/rootfs/usr/local/bin/hyfetch"
srcdir="$repo_root/sources/hyfetch"

mkdir -p "$dl" "$srcdir" "$(dirname "$dest")"

fetch_checked() {
    local file="$1" url="$2" want="$3"
    local path="$dl/$file"
    if [ ! -s "$path" ] || [ "$(sha256sum "$path" | cut -d' ' -f1)" != "$want" ]; then
        echo "fetch  $file"
        curl -fL --retry 3 --connect-timeout 20 --max-time 900 -o "$path.part" "$url"
        mv "$path.part" "$path"
    fi
    local got
    got=$(sha256sum "$path" | cut -d' ' -f1)
    [ "$got" = "$want" ] || { echo "checksum mismatch for $file: $got" >&2; exit 1; }
    echo "ok     $file $got"
}

fetch_checked "$wheel" "$base/$wheel" "$wheel_sha"
fetch_checked "$source_tar" "$base/$source_tar" "$source_sha"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unzip -q "$dl/$wheel" -d "$tmp"

binary="$tmp/hyfetch/rust/hyfetch"
[ -x "$binary" ] || { echo "wheel has no rust/hyfetch binary" >&2; exit 1; }
readelf -l "$binary" | grep -q INTERP && {
    echo "upstream binary is dynamically linked; refusing to vendor it" >&2
    exit 1
}

install -m755 "$binary" "$dest"
cp "$dl/$source_tar" "$srcdir/$source_tar"
cp "$tmp/hyfetch-2.1.1.dist-info/licenses/LICENSE.md" "$srcdir/LICENSE.md"

cat > "$srcdir/SOURCE.txt" <<EOF
hyfetch $version -- prebuilt static musl x86_64 binary
Wheel:   $base/$wheel
         sha256 $wheel_sha
Source:  $base/$source_tar
         sha256 $source_sha
Binary:  rootfs/usr/local/bin/hyfetch
         the wheel's hyfetch/rust/hyfetch, copied verbatim
Refresh: scripts/vendor-hyfetch.sh
EOF

echo "installed $dest"
"$dest" --version
