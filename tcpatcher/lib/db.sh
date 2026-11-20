# /usr/tcpatch/db.json helpers (jq is shipped in TacoLinux's static bundle)

db_init() {
  mkdir -p "$TCPATCH_HOME"
  chmod 755 "$TCPATCH_HOME" 2>/dev/null || true
  if [[ ! -f $DB_FILE ]]; then
    printf '{}\n' > "$DB_FILE"
  elif ! jq -e 'type == "object"' "$DB_FILE" >/dev/null 2>&1; then
    warn "db.json is not a JSON object, resetting it"
    printf '{}\n' > "$DB_FILE"
  fi
}

db_has() { jq -e --arg k "$1" 'has($k)' "$DB_FILE" >/dev/null 2>&1; }

db_get() { # name, field
  jq -r --arg k "$1" --arg f "$2" '.[$k][$f] // empty' "$DB_FILE"
}

db_set() { # name, version, description, target-version, source
  local name="$1" ver="$2" des="$3" tlver="$4" src="$5" tmp
  tmp="$(mktemp "$TCPATCH_HOME/.db.XXXXXX")"
  jq --arg k "$name" --arg ver "$ver" --arg des "$des" \
     --arg tlver "$tlver" --arg src "$src" --arg now "$(date -u +%FT%TZ)" \
     '.[$k] = {
        VER: $ver,
        DES: $des,
        TLVER: $tlver,
        SRC: $src,
        APPLIED_AT: $now
      }' "$DB_FILE" > "$tmp"
  mv "$tmp" "$DB_FILE"
  chmod 644 "$DB_FILE" 2>/dev/null || true
}

db_list_names() { jq -r 'keys[]' "$DB_FILE" 2>/dev/null; }

db_count() { jq 'length' "$DB_FILE" 2>/dev/null || printf '0\n'; }
