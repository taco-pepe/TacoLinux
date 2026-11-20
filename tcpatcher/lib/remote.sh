# remote subscriptions: git/ssh repos and single-file http patches

remote_name() {
  local cfg="$1/remote.cfg" n
  n="$(cfg_get "$cfg" REMOTE_NAME || true)"
  [[ -n $n ]] && { printf '%s\n' "$n"; return 0; }
  basename "$1"
}

remote_url() {
  local ufile="$1/.url"
  [[ -f $ufile ]] && cat "$ufile" || printf 'unknown\n'
}

remote_dir_by_name() {
  local want="$1" d n
  [[ -d $REMOTE_HOME/$want ]] && { printf '%s\n' "$REMOTE_HOME/$want"; return 0; }
  for d in "$REMOTE_HOME"/*; do
    [[ -d $d ]] || continue
    n="$(remote_name "$d")"
    [[ $n == "$want" ]] && { printf '%s\n' "$d"; return 0; }
  done
  return 1
}

remote_fetch() {
  local d="$1"
  if [[ -d "$d/.git" ]]; then
    info "Fetching $(remote_name "$d")..."
    git -C "$d" fetch --all -q 2>/dev/null \
      && git -C "$d" reset --hard '@{u}' -q 2>/dev/null \
      || warn "could not update $(remote_name "$d"); using cached copy"
  fi
}

remote_subscribe() {
  local url="$1" name
  need_cmd git
  mkdir -p "$REMOTE_HOME"
  if [[ $url == *.tcpatch ]]; then
    need_cmd wget
    name="$(basename "$url" .tcpatch)"
    local d="$REMOTE_HOME/$name"
    [[ ! -e $d ]] || die "remote '$name' already exists"
    mkdir -p "$d/patches"
    info "Downloading $url"
    wget -q --show-progress -O "$d/patches/$name.tcpatch" "$url" \
      || die "download failed: $url"
    cat > "$d/remote.cfg" <<EOF
REMOTE_NAME="$name"
STATUS_REMOTE="up"
RP="http"
RVER=1.0.0
EOF
  else
    name="$(basename "$url" .git)"
    local d="$REMOTE_HOME/$name"
    [[ ! -e $d ]] || die "remote '$name' already exists"
    info "Cloning $url"
    git clone -q --depth 1 "$url" "$d" || die "clone failed: $url"
  fi
  printf '%s\n' "$url" > "$d/.url"
  info "Subscribed to $name ($(remote_url "$d"))"
}

remote_list() {
  [[ -d $REMOTE_HOME ]] || { info "No remotes subscribed. Use: tcpatch subscribe URL"; return 0; }
  local d n status rp rver count found=0
  for d in "$REMOTE_HOME"/*; do
    [[ -d $d ]] || continue
    found=1
    n="$(remote_name "$d")"
    status="$(cfg_get "$d/remote.cfg" STATUS_REMOTE || printf 'unknown')"
    rp="$(cfg_get "$d/remote.cfg" RP || printf 'git')"
    rver="$(cfg_get "$d/remote.cfg" RVER || printf '?')"
    count="$(remote_patches "$d" | wc -l)"
    printf '%-18s %-14s %-6s %-8s %s patches\n' "$n" "$status" "$rp" "$rver" "$count"
    printf '                   %s\n' "$(remote_url "$d")"
  done
  [[ $found -eq 1 ]] || info "No remotes subscribed. Use: tcpatch subscribe URL"
}

remote_make() {
  local name="$1" d
  d="$PWD/$name"
  [[ -n $name ]] || die "usage: tcpatch remotes make NAME"
  [[ ! -e $d ]] || die "$d already exists"
  mkdir -p "$d"
  cat > "$d/remote.cfg" <<EOF
REMOTE_NAME="$name"
STATUS_REMOTE="up"
RP="ssh"
RVER=1.0.0
EOF
  cat > "$d/HOWTOADDP.md" <<'EOF'
# Adding a patch to this remote

Each patch is a subdirectory containing a `patch.cfg` and the files that
should be merged into `/` when the patch is applied.

```
remote/
├── remote.cfg
├── HOWTOADDP.md
└── my_patch/
    ├── patch.cfg
    └── usr/local/bin/hello
```

`patch.cfg` example:

```cfg
NAME="my_patch"
DES="Does something useful"
PVER=1.0
TVER=1.0.0
PERM=keep
L=gplv3-only
```

To remove files on apply, list them (one per line) in `remove.list` next to
`patch.cfg`. The user is asked to confirm every removal.

Build and distribute a single file with `tcpatch build my_patch`; subscribers
apply it with `tcpatch apply --local my_patch-1.0.tcpatch`.
EOF
  git -C "$d" init -q
  git -C "$d" add remote.cfg HOWTOADDP.md
  info "Created remote skeleton $d"
}

# Print paths of all patches in a remote (dirs with patch.cfg or *.tcpatch files).
remote_patches() {
  local d="$1" p
  for p in "$d"/*; do
    [[ -e $p ]] || continue
    if [[ -d $p && -f "$p/patch.cfg" ]]; then
      printf '%s\n' "$p"
    elif [[ $p == *.tcpatch ]]; then
      printf '%s\n' "$p"
    elif [[ -d "$p/patches" ]]; then
      local q
      for q in "$p"/patches/*; do
        [[ -e $q ]] && printf '%s\n' "$q"
      done
    fi
  done
}

apply_remote() {
  local spec="$1" rname pname="" d p patchname label
  if [[ $spec == *:* ]]; then
    rname="${spec%%:*}"
    pname="${spec#*:}"
  else
    rname="$spec"
  fi
  d="$(remote_dir_by_name "$rname")" || die "unknown remote: $rname"
  [[ $DRY_RUN -eq 1 ]] || remote_fetch "$d"

  local found=0
  while IFS= read -r p; do
    [[ -n $p ]] || continue
    patch_prepare "$p"
    patch_load_config
    patch_cleanup
    if [[ -n $pname && $pname != "$P_NAME" && $pname != "$(basename "$p" .tcpatch)" ]]; then
      continue
    fi
    found=1
    label="$(remote_name "$d"):$P_NAME"
    patch_apply "$p" "$label" || return 1
  done < <(remote_patches "$d")
  [[ $found -eq 1 ]] || die "no patch matching '$pname' in $rname"
}

apply_all_remotes() {
  local d
  [[ -d $REMOTE_HOME ]] || { info "No remotes subscribed."; return 0; }
  for d in "$REMOTE_HOME"/*; do
    [[ -d $d ]] || continue
    apply_remote "$(basename "$d")"
  done
}
