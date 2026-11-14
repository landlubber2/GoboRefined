#!/bin/bash
# Lab test for gobo-trash-purge with dated fixtures (runs as user lab in a throwaway HOME)
set -u
H=/tmp/trashtest; rm -rf "$H"; mkdir -p "$H/.local/share/Trash/files" "$H/.local/share/Trash/info" "$H/outside"
T="$H/.local/share/Trash"
echo keep > "$H/outside/sentinel.txt"
mk() {  # mk NAME AGE_SPEC(date -d) [dir]
   local n="$1" d
   d=$(date -d "$2" +%Y-%m-%dT%H:%M:%S)
   if [ "${3:-}" = dir ]; then mkdir -p "$T/files/$n/sub/ro"; echo x > "$T/files/$n/sub/ro/f"; chmod 555 "$T/files/$n/sub/ro"; ln -s "$H/outside" "$T/files/$n/link-to-outside"
   else echo data > "$T/files/$n"; fi
   printf '[Trash Info]\nPath=/x/%s\nDeletionDate=%s\n' "$n" "$d" > "$T/info/$n.trashinfo"
}
mk "eight months.txt" "8 months ago"
mk "five months.txt" "5 months ago"
mk "two months.txt" "2 months ago"
mk "two weeks.txt" "2 weeks ago"
mk "olddir" "7 months ago" dir
mk "old -rf *" "9 months ago"
ln -s "$H/outside/sentinel.txt" "$T/files/oldlink"; printf '[Trash Info]\nPath=/x/oldlink\nDeletionDate=%s\n' "$(date -d '1 year ago' +%Y-%m-%dT%H:%M:%S)" > "$T/info/oldlink.trashinfo"
echo y > "$T/files/baddate"; printf '[Trash Info]\nPath=/x/baddate\nDeletionDate=garbage\n' > "$T/info/baddate.trashinfo"
echo y > "$T/files/nodate"; printf '[Trash Info]\nPath=/x/nodate\n' > "$T/info/nodate.trashinfo"
show() { echo "-- $1:"; ls "$T/files" | sort | tr '\n' '|'; echo; }
export HOME="$H"
show start
gobo-trash-purge --auto; show "auto, default (6 months)"
gobo-trash-purge --set-months 3; echo "months=$(gobo-trash-purge --months)"
gobo-trash-purge --auto; show "auto, 3 months"
gobo-trash-purge --set-months 1; gobo-trash-purge --auto; show "auto, 1 month"
gobo-trash-purge --set-months 7 2>&1; echo "months after bad value=$(gobo-trash-purge --months)"
gobo-trash-purge --delete "" ".." "a/b" 2>&1; show "after invalid --delete names"
gobo-trash-purge --empty; show "after --empty"
ls "$T/info" | wc -l | sed 's/^/info files left: /'
cat "$H/outside/sentinel.txt" && echo "sentinel kept"
HOME= gobo-trash-purge --auto 2>&1; HOME=relative gobo-trash-purge --empty 2>&1
cat "$H/.cache/gobo-trash.log"
