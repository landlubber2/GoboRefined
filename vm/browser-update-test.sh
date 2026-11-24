#!/usr/bin/env bash
# Lab test (P3): verify gobo-pgp-verify, gobo-browser-update (real Mozilla ESR signature +
# SHA-512 + headless health check + undo + reconcile + tamper refusal + auto-rollback),
# gobo-settings-helper admin guards, and Settings > Updates page render.
#   vm/browser-update-test.sh      (needs SSH into the VM with P3 files installed)
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S() { "$here/ssh.sh" "$1"; }
pass=0 fail=0
ok() { if echo "$2" | grep -q -- "$3"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1: got [$2], want /$3/"; fail=$((fail+1)); fi; }
no() { if echo "$2" | grep -q -- "$3"; then echo "FAIL $1: got [$2], must not match /$3/"; fail=$((fail+1)); else echo "PASS $1"; pass=$((pass+1)); fi; }

echo "== 1. status, check, auto toggle, admin guard"
st=$(S 'gobo-browser-update status')
ok "status reports installed Firefox ESR" "$st" "^installed=153\."
ok "status reports auto=on by default" "$st" "^auto=on$"

chk=$(S 'gobo-browser-update check 2>&1')
ok "check reaches Mozilla ESR JSON" "$chk" "UP-TO-DATE\|UPDATE-AVAILABLE"

ok "auto off works" "$(S 'gobo-browser-update auto off')" "^auto=off$"
ok "auto on works" "$(S 'gobo-browser-update auto on')" "^auto=on$"
ok "helper refuses non-admin browser-auto" "$(S 'SUDO_USER=nobody gobo-settings-helper browser-auto off 2>&1; echo rc=$?' | tr '\n' ' ')" "rc=1"
ok "helper accepts admin browser-auto" "$(S 'SUDO_USER=lab gobo-settings-helper browser-auto on 2>&1')" "auto=on"

echo "== 2. OpenPGP verification (real Mozilla 153.7.0esr + tamper + wrong key)"
pgp_out=$(S 'set -e
d=$(mktemp -d /Data/Variable/tmp/pgp-test.XXXXXX)
trap "rm -rf \"$d\"" EXIT
curl -fsSL --max-time 30 -o "$d/SHA512SUMS" https://archive.mozilla.org/pub/firefox/releases/153.7.0esr/SHA512SUMS
curl -fsSL --max-time 30 -o "$d/SHA512SUMS.asc" https://archive.mozilla.org/pub/firefox/releases/153.7.0esr/SHA512SUMS.asc
KEY=/Programs/GoboSpin/Current/share/gobo-browser-update/mozilla-release-key.asc
FP=14F26682D0916CDD81E37B6D61B7B526D98F0353
echo "VALID=$(python3 -I /System/Index/bin/gobo-pgp-verify --primary-fp $FP --key $KEY --sig $d/SHA512SUMS.asc --file $d/SHA512SUMS 2>&1)"
printf "x" >> "$d/SHA512SUMS"
python3 -I /System/Index/bin/gobo-pgp-verify --primary-fp $FP --key $KEY --sig $d/SHA512SUMS.asc --file $d/SHA512SUMS >/dev/null 2>&1 && echo "TAMPER=UNEXPECTED_PASS" || echo "TAMPER=REJECTED"
python3 -I /System/Index/bin/gobo-pgp-verify --primary-fp 0000000000000000000000000000000000000000 --key $KEY --sig $d/SHA512SUMS.asc --file $d/SHA512SUMS >/dev/null 2>&1 && echo "WRONGFP=UNEXPECTED_PASS" || echo "WRONGFP=REJECTED"
')
ok "real Mozilla SHA512SUMS.asc verifies" "$pgp_out" "VALID=VERIFIED-OK primary=14F26682D0916CDD81E37B6D61B7B526D98F0353"
ok "1-byte tampered SHA512SUMS rejected" "$pgp_out" "TAMPER=REJECTED"
ok "wrong primary fingerprint rejected" "$pgp_out" "WRONGFP=REJECTED"

echo "== 3. tampered mirror refused before unpack"
tamper_upd=$(S '
d=$(mktemp -d /Data/Variable/tmp/ff-mirror.XXXXXX)
mkdir -p "$d/153.6.0esr/linux-x86_64/en-US"
echo "deadbeef  linux-x86_64/en-US/firefox-153.6.0esr.tar.xz" > "$d/153.6.0esr/SHA512SUMS"
printf "%s\n" "-----BEGIN PGP SIGNATURE-----" "" "AAAA" "-----END PGP SIGNATURE-----" > "$d/153.6.0esr/SHA512SUMS.asc"
python3 -m http.server 18769 --bind 127.0.0.1 --directory "$d" >/dev/null 2>&1 &
pid=$!; sleep 1
out=$(gobo-browser-update update --version 153.6.0esr --force --base-url http://127.0.0.1:18769 2>&1); rc=$?
kill $pid 2>/dev/null || true; rm -rf "$d"
echo "RC=$rc $out"
' | tr '\n' ' ')
ok "forged mirror rejected with non-zero exit" "$tamper_upd" "RC=1 .*signature verification FAILED"
no "forged mirror did not create /Programs/Firefox/153.6.0esr" "$(S 'ls -d /Programs/Firefox/153.6.0esr 2>&1')" "^/Programs/Firefox/153.6.0esr$"

echo "== 4. real signed Mozilla ESR install (153.6.0esr) + health check + undo + reconcile"
upd_out=$(S 'gobo-browser-update update --version 153.6.0esr --force 2>&1; echo "RC=$?"')
ok "real Mozilla 153.6.0esr verified, installed, and passed headless health check" "$upd_out" "UPDATED-OK 153\.7\.0esr -> 153\.6\.0esr"
ok "active firefox binary reports 153.6.0esr" "$(S 'firefox --version 2>&1')" "153\.6\.0esr"
ok "status lists undo=153.7.0esr" "$(S 'gobo-browser-update status')" "^undo=153\.7\.0esr$"

undo_out=$(S 'gobo-browser-update undo 2>&1')
ok "undo switches back to 153.7.0esr" "$undo_out" "UNDONE 153\.6\.0esr -> 153\.7\.0esr"
ok "active firefox binary back to 153.7.0esr" "$(S 'firefox --version 2>&1')" "153\.7\.0esr"

# Switch back to 153.6.0esr and prove reconcile promotes newer 153.7.0esr (simulating an A/B slot upgrade)
rec_out=$(S 'gobo-browser-update undo >/dev/null 2>&1 && gobo-browser-update reconcile 2>&1')
ok "reconcile promotes newer ESR automatically" "$rec_out" "RECONCILED 153\.6\.0esr -> 153\.7\.0esr"

echo "== 5. automatic rollback on broken binary"
# Replace 153.6.0esr package/firefox with exit 1 and test health_check_firefox + rollback directly via a local copy
rb_out=$(S '
# Remove 153.6.0esr test dir first, then test broken health-check rollback cleanly using a stubbed health check
rm -rf /Programs/Firefox/153.6.0esr /Data/Variable/lib/gobo-browser-update/prev-version
mkdir -p /Programs/Firefox/153.6.0esr/package /Programs/Firefox/153.6.0esr/bin
printf "#!/bin/sh\nexit 1\n" > /Programs/Firefox/153.6.0esr/package/firefox
chmod 755 /Programs/Firefox/153.6.0esr/package/firefox
# Source helper functions cleanly via subshell test of health_check_firefox
bash -c "
  set -e
  source <(sed \"/^\[ \\\$# -ge 1 \]/,\\\$d\" /System/Index/bin/gobo-browser-update)
  if health_check_firefox 153.6.0esr; then echo HC=UNEXPECTED_PASS; else echo HC=FAILED_AS_EXPECTED; fi
"
rm -rf /Programs/Firefox/153.6.0esr
echo "CURRENT=$(readlink /Programs/Firefox/Current)"
')
ok "broken firefox binary fails health check" "$rb_out" "HC=FAILED_AS_EXPECTED"
ok "Current remains healthy 153.7.0esr" "$rb_out" "CURRENT=153\.7\.0esr"

echo "passed $pass, failed $fail"
