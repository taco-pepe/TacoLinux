# shared helpers for tcpatch
# shellcheck shell=bash

# Every path that ends up on the target system is built through rpath().
# Set TCPATCH_ROOT to point at a sandbox tree (used by the test suite).
TCPATCH_ROOT="${TCPATCH_ROOT:-/}"
ROOT="${TCPATCH_ROOT%/}"
[[ -z $ROOT ]] && ROOT=/

rpath() {
  local p="${1#/}"
  if [[ $ROOT == / ]]; then printf '/%s' "$p"; else printf '%s/%s' "$ROOT" "$p"; fi
}

TCPATCH_HOME="${TCPATCH_HOME:-$(rpath usr/tcpatch)}"

DRY_RUN=0
FORCE=0
ASSUME_YES=0
VERBOSE=0

DB_FILE="$TCPATCH_HOME/db.json"
REMOTE_HOME="$TCPATCH_HOME/remotes"

need_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "missing required command: $c"
  done
}

die() { printf 'tcpatch: %s\n' "$*" >&2; exit 1; }
warn() { printf 'tcpatch: warning: %s\n' "$*" >&2; }
info() { printf '%s\n' "$*"; }
step() { printf '%s\n' "$*"; }

# Parse a KEY="value" # comment config file WITHOUT sourcing it.
# Remote-provided files must never be executed as shell code.
cfg_get() {
  local file="$1" key="$2"
  [[ -f $file ]] || return 1
  awk -v want="$key" '
    /^[[:space:]]*(#|$)/ { next }
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      eq = index(line, "=")
      if (!eq) next
      k = substr(line, 1, eq - 1)
      v = substr(line, eq + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
      sub(/^[[:space:]]+/, "", v)
      if (k != want) next
      if (v ~ /^["\047]/) {
        q = substr(v, 1, 1)
        rest = substr(v, 2)
        out = ""
        for (i = 1; i <= length(rest); i++) {
          c = substr(rest, i, 1)
          if (c == q) break
          if (c == "\\" && substr(rest, i + 1, 1) == q) {
            out = out q; i++; continue
          }
          out = out c
        }
        print out; exit
      }
      sub(/[[:space:]]*#.*$/, "", v)
      gsub(/[[:space:]]+$/, "", v)
      print v; exit
    }
  ' "$file"
}

# Prompts always come from fd 4, never from a loop's redirected stdin.
PROMPT_FD=4

# Ask a y/n question. The capital letter in the suffix marks the default,
# exactly like the design doc describes. Both y/n and yes/no are accepted.
ask_yn() {
  local prompt="$1" def="${2:-y}" answer suffix
  [[ $def == y ]] && suffix='[Y/n]' || suffix='[y/N]'
  while true; do
    if [[ $ASSUME_YES -eq 1 ]]; then
      answer=''
    else
      read -r -u "$PROMPT_FD" -p "$prompt $suffix " answer || answer=''
    fi
    case "${answer,,}" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      '')   [[ $def == y ]] && return 0 || return 1 ;;
      *)    printf 'Please answer y or n.\n' >&2 ;;
    esac
  done
}

# TacoLinux keeps its version in /usr/distro/version.cfg per the design;
# older/current images only have /etc/os-release. Accept both.
system_version() {
  local f
  f="$(rpath usr/distro/version.cfg)"
  if [[ -f $f ]]; then
    local v; v="$(cfg_get "$f" VER || true)"
    [[ -n $v ]] && { printf '%s\n' "$v"; return 0; }
  fi
  f="$(rpath etc/os-release)"
  if [[ -f $f ]]; then
    local v; v="$(cfg_get "$f" VERSION_ID || true)"
    [[ -n $v ]] && { printf '%s\n' "$v"; return 0; }
  fi
  printf 'unknown\n'
}

ver_ge() { # $1 >= $2
  [[ $1 == "$2" ]] && return 0
  if command -v sort >/dev/null 2>&1; then
    local lo hi
    lo="$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)"
    hi="$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)"
    [[ $hi == "$1" ]] && return 0
  fi
  return 1
}

progress_line() { # label, path, percent, eta_seconds
  local label="$1" path="$2" pct="$3" eta="$4" filled width=30 bar
  (( pct < 0 )) && pct=0
  (( pct > 100 )) && pct=100
  filled=$(( pct * width / 100 ))
  (( filled > width - 1 )) && filled=$((width - 1))
  bar="$(printf '%*s' "$filled" '' | tr ' ' '-')|$(printf '%*s' $((width - filled - 1)) '')"
  printf '%s:\n      %s -> %s [%s] %5.1f%% ETA=%ss\n' "$label" "${path##*/}" "$path" "$bar" "$pct" "$eta"
}

# Print the DB entry summary in the same shape as the design doc example.
json_escape() { printf '%s' "$1" | jq -Rs .; }
