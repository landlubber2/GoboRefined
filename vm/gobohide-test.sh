#!/usr/bin/env bash
# Lab test (P2/P6): verify GoboHide kernel support and hiding/unhiding behavior.
#   vm/gobohide-test.sh        (needs SSH into the VM as root)
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S() { "$here/ssh.sh" "$1"; }
pass=0 fail=0
ok() { if echo "$2" | grep -q -- "$3"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1: got [$2], want /$3/"; fail=$((fail+1)); fi; }
no() { if echo "$2" | grep -q -- "$3"; then echo "FAIL $1: got [$2], must not match /$3/"; fail=$((fail+1)); else echo "PASS $1"; pass=$((pass+1)); fi; }

cfg=$(S 'if [ -r /proc/config.gz ]; then zcat /proc/config.gz | grep "^CONFIG_GOBOHIDE_FS="; else echo "CONFIG_GOBOHIDE_FS=unknown"; fi')
ok "kernel config has CONFIG_GOBOHIDE_FS=y" "$cfg" "CONFIG_GOBOHIDE_FS=y"

list=$(S 'gobohide -l 2>&1')
ok "gobohide -l lists /usr" "$list" "^/usr$"
ok "gobohide -l lists /bin" "$list" "^/bin$"
ok "gobohide -l lists /etc" "$list" "^/etc$"
ok "gobohide -l lists /var" "$list" "^/var$"

rootls=$(S 'ls -1 /')
ok "root listing shows /Programs" "$rootls" "^Programs$"
ok "root listing shows /System" "$rootls" "^System$"
ok "root listing shows /Users" "$rootls" "^Users$"
no "root listing hides usr" "$rootls" "^usr$"
no "root listing hides bin" "$rootls" "^bin$"
no "root listing hides etc" "$rootls" "^etc$"
no "root listing hides var" "$rootls" "^var$"

# Hide/unhide round-trip in a temporary directory under /Data/Variable/tmp
rt=$(S 'set -e
d=$(mktemp -d /Data/Variable/tmp/gobohide-test.XXXXXX)
trap "gobohide -u \"$d/secret\" 2>/dev/null || true; rm -rf \"$d\"" EXIT
mkdir "$d/secret" "$d/visible"
before=$(ls -1 "$d" | tr "\n" ",")
gobohide -h "$d/secret"
hidden=$(ls -1 "$d" | tr "\n" ",")
direct=$([ -d "$d/secret" ] && echo reachable || echo missing)
gobohide -u "$d/secret"
after=$(ls -1 "$d" | tr "\n" ",")
printf "before=%s hidden=%s direct=%s after=%s\n" "$before" "$hidden" "$direct" "$after"')

ok "round-trip: secret hidden from readdir" "$rt" "hidden=visible,"
ok "round-trip: hidden dir still directly reachable" "$rt" "direct=reachable"
ok "round-trip: unhide restores visibility" "$rt" "after=secret,visible,"

echo "passed $pass, failed $fail"
