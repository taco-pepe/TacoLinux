# patch creation, packaging and application

P_DIR=""
P_TMPDIR=""

patch_cleanup() {
  [[ -n $P_TMPDIR && -d $P_TMPDIR ]] && rm -rf -- "$P_TMPDIR"
  P_DIR=""
  P_TMPDIR=""
}

_is_zstd() {
  local magic
  magic="$(dd if="$1" bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
  [[ $magic == 28b52ffd ]]
}

# Unpack a single-file .tcpatch into a temp dir. Format is deliberately simple
# so it can be read with only the static tools TacoLinux ships:
#   TCPATCH1\n
#   F\t<mode>\t<relpath>\n<base64-of-file, one line>\n
#   D\t<mode>\t<relpath>\n
#   L\t<link-target>\t<relpath>\n
#   X\t<relpath-to-delete>\n
#   END\n
# The whole thing may be wrapped in a zstd frame (no tar/gzip needed).
patch_extract() {
  local archive="$1" work raw magic kind a b line
  work="$(mktemp -d "${TMPDIR:-/tmp}/tcpatch.XXXXXX")"
  P_TMPDIR="$work"
  raw="$work/raw.tcpatch"

  if _is_zstd "$archive"; then
    need_cmd zstd
    zstd -q -dc "$archive" > "$raw" || die "cannot decompress $archive"
  else
    cp -- "$archive" "$raw"
  fi

  mkdir -p "$work/patch"
  exec 3< "$raw"
  IFS= read -r -u 3 magic || die "empty patch archive"
  [[ $magic == TCPATCH1 ]] || die "not a .tcpatch archive: $archive"
  while IFS= read -r -u 3 line; do
    [[ $line == END ]] && break
    IFS=$'\t' read -r kind a b <<< "$line"
    case "$kind" in
      D)
        mkdir -p "$work/patch/$b"
        chmod "$a" "$work/patch/$b" 2>/dev/null || true
        ;;
      F)
        IFS= read -r -u 3 line || die "truncated archive: missing data for $b"
        mkdir -p "$(dirname "$work/patch/$b")"
        printf '%s' "$line" | base64 -d > "$work/patch/$b" \
          || die "bad base64 payload for $b"
        chmod "$a" "$work/patch/$b" 2>/dev/null || true
        ;;
      L)
        mkdir -p "$(dirname "$work/patch/$b")"
        ln -s -- "$a" "$work/patch/$b" 2>/dev/null || true
        ;;
      X)
        printf '%s\n' "$a" >> "$work/patch/remove.list"
        ;;
      *) warn "unknown archive entry type '$kind' in $archive" ;;
    esac
  done
  exec 3<&-
  P_DIR="$work/patch"
}

# Accept either a patch project directory or a built single-file .tcpatch.
patch_prepare() {
  local src="$1"
  [[ -e $src ]] || die "patch not found: $src"
  if [[ -d $src ]]; then
    P_DIR="$(cd "$src" && pwd)"
    P_TMPDIR=""
  else
    patch_extract "$src"
  fi
  [[ -f $P_DIR/patch.cfg ]] || die "patch has no patch.cfg: $src"
}

# Load patch.cfg into P_NAME/P_DES/PVER/P_TVER/P_PERM/P_LIC.
patch_load_config() {
  local f="$P_DIR/patch.cfg"
  P_NAME="$(cfg_get "$f" NAME || true)"
  P_DES="$(cfg_get "$f" DES || true)"
  PVER="$(cfg_get "$f" PVER || true)"
  P_TVER="$(cfg_get "$f" TVER || true)"
  P_PERM="$(cfg_get "$f" PERM || true)"
  P_LIC="$(cfg_get "$f" L || true)"
  [[ -n $P_NAME ]] || P_NAME="$(basename "$P_DIR")"
  [[ -n $PVER ]] || PVER="0.0"
  [[ -n $P_PERM ]] || P_PERM="keep"
  [[ -n $P_LIC ]] || P_LIC="unknown"
  case "$P_PERM" in
    keep|allroot|alluser) ;;
    *) warn "unknown PERM '$P_PERM' in $f, using 'keep'"; P_PERM=keep ;;
  esac
}

patch_new() {
  local name="$1" dir="${2:-$1}"
  [[ -n $name ]] || die "usage: tcpatch new NAME [DIR]"
  [[ ! -e $dir ]] || die "$dir already exists"
  mkdir -p "$dir"
  cat > "$dir/patch.cfg" <<EOF
NAME="$name"
DES="A patch for tacolinux"
PVER=1.0
TVER=$(system_version)
PERM=keep
L=gplv3-only
EOF
  printf '# One path per line, relative to / (leading / is fine too).\n' > "$dir/remove.list"
  mkdir -p "$dir/etc" "$dir/usr/local/bin"
  printf 'Created patch project %s\n' "$dir"
  printf 'Edit %s/patch.cfg and put payload files in %s/, then:\n' "$dir" "$dir"
  printf '  tcpatch build %s\n' "$dir"
}

patch_build() {
  local src="${1:-.}" out="${2:-}"
  need_cmd jq base64 stat find zstd
  [[ -d $src ]] || die "not a patch directory: $src"
  [[ -f $src/patch.cfg ]] || die "$src has no patch.cfg"
  src="$(cd "$src" && pwd)"

  local name ver raw line rel mode f
  name="$(cfg_get "$src/patch.cfg" NAME || true)"
  ver="$(cfg_get "$src/patch.cfg" PVER || true)"
  [[ -n $name ]] || name="$(basename "$src")"
  [[ -n $ver ]] || ver="1.0"
  out="${out:-$src/dist/$name-$ver.tcpatch}"
  mkdir -p "$(dirname "$out")"

  raw="$(mktemp "${TMPDIR:-/tmp}/tcpatch-build.XXXXXX")"
  printf 'TCPATCH1\n' > "$raw"

  while IFS= read -r -d '' f; do
    rel="${f#"$src"/}"
    mode="$(stat -c %a "$f" 2>/dev/null || printf '644')"
    if [[ -L $f ]]; then
      printf 'L\t%s\t%s\n' "$(readlink "$f")" "$rel" >> "$raw"
    elif [[ -d $f ]]; then
      printf 'D\t%s\t%s\n' "$mode" "$rel" >> "$raw"
    elif [[ -f $f ]]; then
      printf 'F\t%s\t%s\n' "$mode" "$rel" >> "$raw"
      base64 < "$f" | tr -d '\n' >> "$raw"
      printf '\n' >> "$raw"
    fi
  done < <(find "$src" -mindepth 1 \( -name .git -o -name dist \) -prune -o -print0)

  if [[ -f "$src/remove.list" ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      line="${line%%#*}"
      line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      [[ -z $line ]] && continue
      printf 'X\t%s\n' "${line#/}" >> "$raw"
    done < "$src/remove.list"
  fi

  printf 'END\n' >> "$raw"
  if command -v zstd >/dev/null 2>&1; then
    zstd -q -f -o "$out" "$raw"
  else
    mv "$raw" "$out"
  fi
  rm -f -- "$raw"
  printf 'Built %s\n' "$out"
}

_payload_paths() {
  local f
  find "$P_DIR" -mindepth 1 \( -name patch.cfg -o -name remove.list -o -name .git -o -name dist \) -prune -o -print
}

_apply_permissions() {
  local f rel target mode
  [[ $P_PERM == keep ]] && return 0
  while IFS= read -r f; do
    rel="${f#"$P_DIR"/}"
    target="$(rpath "$rel")"
    [[ -e $target || -L $target ]] || continue
    if [[ $EUID -eq 0 ]]; then
      if [[ $P_PERM == allroot ]]; then
        chown -h 0:0 "$target" 2>/dev/null || true
      else
        chown -h 1000:1000 "$target" 2>/dev/null || true
      fi
    fi
    if [[ -d $target ]]; then
      chmod 755 "$target" 2>/dev/null || true
    elif [[ -f $target ]]; then
      chmod 644 "$target" 2>/dev/null || true
      mode="$(stat -c %a "$target" 2>/dev/null || printf '644')"
      # keep the execute bit the patch author shipped
      if (( 8#$mode & 0111 )); then chmod +x "$target" 2>/dev/null || true; fi
    fi
  done < <(_payload_paths)
}

patch_apply() {
  local src="$1" label="${2:-local}" total=0 i=0 start eta pct
  need_cmd jq rsync base64

  patch_prepare "$src"
  patch_load_config
  [[ $DRY_RUN -eq 1 ]] || db_init

  local sysver
  sysver="$(system_version)"
  info "Applying $P_NAME ($PVER) from $label"
  info "  description: $P_DES"
  info "  license:     $P_LIC"
  info "  permissions: $P_PERM"
  info "  target TacoLinux: $P_TVER (system: $sysver)"

  if [[ -n $P_TVER && $sysver != unknown && $P_TVER != "$sysver" ]] && [[ $FORCE -eq 0 ]]; then
    warn "patch targets TacoLinux $P_TVER but this system is $sysver"
    ask_yn "Apply anyway?" n || die "aborted: version mismatch (use --force to override)"
  fi

  if db_has "$P_NAME" && [[ $FORCE -eq 0 ]]; then
    local oldver
    oldver="$(db_get "$P_NAME" VER)"
    if [[ -n $PVER && $PVER != "$oldver" ]] && ver_ge "$PVER" "$oldver"; then
      if ask_yn "$P_NAME v$oldver is applied; upgrade to v$PVER?" y; then
        : # continue and overwrite the database entry
      else
        return 0
      fi
    else
      info "$P_NAME v$oldver is already applied; skipping."
      return 0
    fi
  fi

  if [[ $DRY_RUN -eq 0 ]]; then
    if [[ $ASSUME_YES -eq 0 ]]; then
      ask_yn "Are you sure you want to apply $P_NAME from $label?" y \
        || die "aborted"
    fi
  else
    info "[dry-run] would apply $P_NAME from $label"
  fi

  # Removals are opt-in, one question per file, default NO.
  local rmfile="$P_DIR/remove.list" line target
  if [[ -f $rmfile ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      line="${line%%#*}"
      line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      [[ -z $line ]] && continue
      target="$(rpath "$line")"
      if [[ ! -e $target && ! -L $target ]]; then continue; fi
      if [[ $DRY_RUN -eq 1 ]]; then
        info "[dry-run] $P_NAME wants to remove $target"
      elif ask_yn "$P_NAME wants to remove $target allow?" n; then
        rm -rf -- "$target"
        info "Removed $target"
      else
        info "Kept $target"
      fi
    done < "$rmfile"
  fi

  total="$(_payload_paths | wc -l)"
  start="$(date +%s)"
  i=0
  while IFS= read -r f; do
    i=$((i + 1))
    rel="${f#"$P_DIR"/}"
    target="$(rpath "$rel")"
    pct=$(( total == 0 ? 100 : i * 100 / total ))
    eta=$(( i == 0 ? 0 : (total - i) * ($(date +%s) - start) / i ))
    progress_line "$P_NAME" "$target" "$pct" "$eta"
  done < <(_payload_paths)

  if [[ $DRY_RUN -eq 1 ]]; then
    rsync -an --exclude=/patch.cfg --exclude=/remove.list --exclude=/.git \
      "$P_DIR/" "$ROOT/" | sed 's/^/[dry-run] /'
  else
    rsync -a --exclude=/patch.cfg --exclude=/remove.list --exclude=/.git \
      "$P_DIR/" "$ROOT/"
    _apply_permissions
    if [[ $ROOT == / ]] && command -v systemctl >/dev/null 2>&1; then
      info "Reloading systemd daemon."
      systemctl daemon-reload >/dev/null 2>&1 || warn "systemctl daemon-reload failed"
    else
      info "Skipping systemd daemon-reload (sandbox root)."
    fi
    info "Adding patch to database."
    db_set "$P_NAME" "$PVER" "$P_DES" "$P_TVER" "$label"
  fi

  info "Done. nothing else to do :D"
  patch_cleanup
}
