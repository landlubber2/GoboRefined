#!/usr/bin/env bash
# Clone key GoboLinux repos into ../upstream/
# Usage:
#   ./scripts/clone-upstream.sh
#   ./scripts/clone-upstream.sh --with-recipes   # also clone Recipes (large)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${ROOT}/upstream"
ORG="https://github.com/gobolinux"
WITH_RECIPES=0

for arg in "$@"; do
  case "$arg" in
    --with-recipes) WITH_RECIPES=1 ;;
    -h|--help)
      echo "Usage: $0 [--with-recipes]"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

mkdir -p "$DEST"

clone_one() {
  local name="$1"
  local target="${DEST}/${name}"
  if [[ -d "${target}/.git" ]]; then
    echo "Already cloned: ${name} (pulling)"
    git -C "$target" pull --ff-only
  elif [[ -e "$target" ]]; then
    echo "Skip ${name}: path exists but is not a git repo: ${target}" >&2
  else
    echo "Cloning ${name}..."
    git clone --depth 1 "${ORG}/${name}.git" "$target"
  fi
}

# Default set (skip Recipes — large)
clone_one Documentation
clone_one Scripts
clone_one Compile
clone_one LiveCD

if [[ "$WITH_RECIPES" -eq 1 ]]; then
  clone_one Recipes
else
  echo "Skipped Recipes (large). Pass --with-recipes to clone it."
fi

echo "Done. Repos under: ${DEST}"
