#!/bin/bash
# Local end-to-end tests. Everything happens inside a sandbox root.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TCPATCH="$HERE/tcpatch"
WORK="/tmp/opencode/tcpatch-tests"
rm -rf "$WORK"
mkdir -p "$WORK"

PASS=0
FAIL=0
ok()   { printf '  ok   %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL %s\n' "$1"; FAIL=$((FAIL + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
eq()   { if [[ $2 == "$3" ]]; then ok "$1"; else bad "$1 (got: $2)"; fi; }

banner() { printf '\n== %s ==\n' "$1"; }

banner "cli basics"
check "help works" "$TCPATCH --help | grep -q 'apply --local'"

banner "new / build / apply (directory)"
mkdir -p "$WORK/sandbox1/usr/distro" "$WORK/sandbox1/etc"
printf 'VER=1.0.0\n' > "$WORK/sandbox1/usr/distro/version.cfg"
printf 'VERSION_ID="1.0.0"\n' > "$WORK/sandbox1/etc/os-release"
cd "$WORK"
"$TCPATCH" new hello >/dev/null
sed -i 's/^TVER=.*/TVER=1.0.0/' "$WORK/hello/patch.cfg"
check "patch.cfg generated" "grep -q 'NAME=\"hello\"' hello/patch.cfg"
printf 'hello from tcpatch\n' > "$WORK/hello/usr/local/bin/hello-teto"
chmod 755 "$WORK/hello/usr/local/bin/hello-teto"
"$TCPATCH" build "$WORK/hello" >/dev/null
check "archive built" "[[ -f $WORK/hello/dist/hello-1.0.tcpatch ]]"
"$TCPATCH" apply --local "$WORK/hello" --root "$WORK/sandbox1" --yes > "$WORK/apply1.log" 2>&1
eq "payload deployed" "$(cat $WORK/sandbox1/usr/local/bin/hello-teto)" "hello from tcpatch"
check "executable bit kept" "[[ -x $WORK/sandbox1/usr/local/bin/hello-teto ]]"
check "db written" "jq -e 'has(\"hello\")' $WORK/sandbox1/usr/tcpatch/db.json >/dev/null"
eq "db version" "$(jq -r '.hello.VER' $WORK/sandbox1/usr/tcpatch/db.json)" "1.0"
check "done message" "grep -q 'nothing else to do' $WORK/apply1.log"
"$TCPATCH" apply --local "$WORK/hello" --root "$WORK/sandbox1" --yes > "$WORK/apply2.log" 2>&1
check "second apply skips" "grep -q 'already applied' $WORK/apply2.log"

banner "single-file archive + dry run"
mkdir -p "$WORK/sandbox2/etc"
printf 'VERSION_ID="1.0.0"\n' > "$WORK/sandbox2/etc/os-release"
"$TCPATCH" apply --local "$WORK/hello/dist/hello-1.0.tcpatch" --root "$WORK/sandbox2" --yes --dry-run > "$WORK/dry.log" 2>&1
check "dry run says so" "grep -q '\[dry-run\]' $WORK/dry.log"
check "dry run made no db" "[[ ! -e $WORK/sandbox2/usr/tcpatch/db.json ]]"
"$TCPATCH" apply --local "$WORK/hello/dist/hello-1.0.tcpatch" --root "$WORK/sandbox2" --yes >/dev/null 2>&1
check "archive applied" "[[ -f $WORK/sandbox2/usr/local/bin/hello-teto ]]"
check "archive db" "jq -e 'has(\"hello\")' $WORK/sandbox2/usr/tcpatch/db.json >/dev/null"

banner "removals ask first (default no), yes removes"
mkdir -p "$WORK/sandbox3/etc" "$WORK/sandbox3/usr/local/bin"
printf 'VERSION_ID="1.0.0"\n' > "$WORK/sandbox3/etc/os-release"
printf 'obsolete\n' > "$WORK/sandbox3/usr/local/bin/old-tool"
printf '/usr/local/bin/old-tool\n' > "$WORK/hello/remove.list"
printf 'y\nn\n' | "$TCPATCH" apply --local "$WORK/hello" --root "$WORK/sandbox3" > "$WORK/rm-no.log" 2>&1
check "declined removal keeps file" "[[ -f $WORK/sandbox3/usr/local/bin/old-tool ]]"
rm "$WORK/sandbox3/usr/tcpatch/db.json"
printf 'y\ny\n' | "$TCPATCH" apply --local "$WORK/hello" --root "$WORK/sandbox3" --force > "$WORK/rm-yes.log" 2>&1
check "approved removal deletes file" "[[ ! -e $WORK/sandbox3/usr/local/bin/old-tool ]]"
printf '# nothing\n' > "$WORK/hello/remove.list"

banner "remotes"
cd "$WORK"
"$TCPATCH" remotes make teto-repo >/dev/null
cp -r "$WORK/hello" "$WORK/teto-repo/hello"
git -C "$WORK/teto-repo" add -A >/dev/null 2>&1
git -C "$WORK/teto-repo" -c user.email=t@x -c user.name=t commit -q -m init >/dev/null 2>&1
mkdir -p "$WORK/sandbox4/etc"
printf 'VERSION_ID="1.0.0"\n' > "$WORK/sandbox4/etc/os-release"
export TCPATCH_HOME="$WORK/sandbox4/usr/tcpatch"
"$TCPATCH" subscribe "$WORK/teto-repo" > "$WORK/sub.log" 2>&1
check "subscribed" "grep -q 'Subscribed to teto-repo' $WORK/sub.log"
check "remotes lists it" "[[ \$($TCPATCH remotes) == *teto-repo* ]]"
"$TCPATCH" status > "$WORK/status.log" 2>&1
check "status mentions version" "grep -q 'TacoLinux version' $WORK/status.log"
"$TCPATCH" apply teto-repo --root "$WORK/sandbox4" --home "$WORK/sandbox4/usr/tcpatch" --yes > "$WORK/remote-apply.log" 2>&1
check "remote patch applied" "[[ -f $WORK/sandbox4/usr/local/bin/hello-teto ]]"
check "remote label in db" "jq -e '.hello.SRC == \"teto-repo:hello\"' $WORK/sandbox4/usr/tcpatch/db.json >/dev/null"
check "update is dry-runnable" "$TCPATCH update --dry-run --root $WORK/sandbox4 --home $WORK/sandbox4/usr/tcpatch --yes >/dev/null 2>&1"
unset TCPATCH_HOME

banner "config parser does not execute config content"
mkdir -p "$WORK/evil"
{
  printf 'NAME="evil"\n'
  printf 'DES="$(touch /tmp/opencode/tcpatch-tests/PWNED)"\n'
  printf 'PVER=1.0\nTVER=1.0.0\nPERM=keep\n'
} > "$WORK/evil/patch.cfg"
# shellcheck source=/dev/null
source "$HERE/lib/common.sh"
des_val="$(cfg_get "$WORK/evil/patch.cfg" DES)"
if [[ $des_val == '$(touch /tmp/opencode/tcpatch-tests/PWNED)' ]]; then
  ok "config value is literal, not executed"
else
  bad "config value was mangled: $des_val"
fi
check "injection file absent" "[[ ! -e $WORK/PWNED ]]"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
