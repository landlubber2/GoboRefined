#!/usr/bin/env bash
# Copy this checkout into the lab VM, as an outsider's clone would look: only the files git
# tracks or would track (new files not ignored by .gitignore), with uncommitted edits, no
# lab secrets. Nothing is committed (a temporary index is used; git keeps only loose objects).
#
#   vm/push-repo.sh [DEST]      over SSH into the VM, default /Data/Build/repo (replaced)
#   vm/push-repo.sh --tarball   write vm/serve/goborefined-src.tgz for the lab file server
#                               (guest: wget http://10.0.2.2:8766/goborefined-src.tgz)
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here/.."
idx=$(mktemp)
trap 'rm -f "$idx"' EXIT
cp "$(git rev-parse --git-path index)" "$idx"
GIT_INDEX_FILE=$idx git add -A
tree=$(GIT_INDEX_FILE=$idx git write-tree)
if [ "${1:-}" = --tarball ]
then
   git -c core.autocrlf=false archive --format=tar.gz --prefix=goborefined/ -o vm/serve/goborefined-src.tgz "$tree"
   ls -l vm/serve/goborefined-src.tgz
else
   dest=${1:-/Data/Build/repo}
   case "$dest" in /*) ;; *) echo "DEST must be absolute"; exit 1 ;; esac
   git -c core.autocrlf=false archive --format=tar "$tree" |
      "$here/ssh.sh" "rm -rf '$dest' && mkdir -p '$dest' && tar xf - -C '$dest' && echo 'repository copied to $dest'"
fi
