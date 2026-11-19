#!/usr/bin/env bash
# Vendor the sources of TacoLinux's bundled CLI tools into sources/.
#
# - Downloads each archive listed in scripts/cli-tools/apps.tsv
# - Extracts it to sources/<subdir>
# - Removes any .git directory left inside the tree
# - Writes sources/SHA256SUMS
#
# Usage: scripts/fetch-cli-sources.sh [name ...]
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
manifest="$repo_root/scripts/cli-tools/apps.tsv"
src_root="$repo_root/sources"
dl_root="$repo_root/.cache/downloads"

mkdir -p "$src_root" "$dl_root"

only=("$@")
want() {
    [ ${#only[@]} -eq 0 ] && return 0
    local n
    for n in "${only[@]}"; do [ "$n" = "$1" ] && return 0; done
    return 1
}

fetch_one() {
    local name="$1" version="$2" dir="$3" url="$4"
    local dest="$src_root/$dir"

    if [ -d "$dest" ] && [ -n "$(ls -A "$dest" 2>/dev/null)" ]; then
        echo "skip   $name (already vendored in sources/$dir)"
        return 0
    fi

    local file="$dl_root/$(basename "${url%%\?*}")"
    if [ ! -s "$file" ]; then
        echo "fetch  $name $version"
        curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 \
             --max-time 900 -o "$file.part" "$url"
        mv "$file.part" "$file"
    else
        echo "cached $name $version"
    fi

    local tmp
    tmp=$(mktemp -d)
    # GNU tar auto-detects gzip/xz/bzip2
    if ! tar -xf "$file" -C "$tmp"; then
        echo "error: could not extract $file" >&2
        rm -rf "$tmp"
        return 1
    fi

    local entries
    entries=$(ls -A "$tmp" | wc -l)
    if [ "$entries" -eq 1 ] && [ -d "$tmp/$(ls -A "$tmp")" ]; then
        mv "$tmp/$(ls -A "$tmp")" "$dest"
    else
        mkdir -p "$dest"
        mv "$tmp"/* "$dest"/ 2>/dev/null || true
    fi
    rm -rf "$tmp"

    find "$dest" -type d -name .git -prune -exec rm -rf {} + 2>/dev/null || true
    echo "done   $name -> sources/$dir"
}

failed=0
while IFS=$'\t' read -r name version dir url recipe; do
    case "$name" in ''|'#'*) continue ;; esac
    want "$name" || continue
    fetch_one "$name" "$version" "$dir" "$url" || failed=$((failed + 1))
done < "$manifest"

# Checksums: upstream archives (in .cache/downloads) plus a digest of each
# vendored tree.  Format: <sha256>  <label>
(
    cd "$src_root"
    {
        echo "# sha256 checksums of the upstream archives fetched for sources/"
        echo "# verify an archive with: sha256sum -c <(grep <name> SHA256SUMS)"
        while IFS=$'\t' read -r name version dir url recipe; do
            case "$name" in ''|'#'*) continue ;; esac
            [ -d "$dir" ] || continue
            file="$dl_root/$(basename "${url%%\?*}")"
            if [ -s "$file" ]; then
                printf '%s  %s\n' "$(sha256sum "$file" | cut -d' ' -f1)" "$name-$version-$(basename "${url%%\?*}")"
            fi
        done < "$manifest"
        echo "# digest of the extracted tree (sorted file list + contents)"
        while IFS=$'\t' read -r name version dir url recipe; do
            case "$name" in ''|'#'*) continue ;; esac
            [ -d "$dir" ] || continue
            printf '%s  tree:%s\n' "$(find "$dir" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)" "$name"
        done < "$manifest"
    } > SHA256SUMS
)

echo
echo "vendored: $(find "$src_root" -mindepth 1 -maxdepth 1 -type d | wc -l) source trees, $(du -sh "$src_root" | cut -f1) total"
[ "$failed" -eq 0 ] || { echo "FAILED fetches: $failed" >&2; exit 1; }
