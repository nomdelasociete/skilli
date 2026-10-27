#!/usr/bin/env bash
# The user guides' pictures (skil.li/guides): copies what
# `./script/build_and_run.sh remote guides` brought back (dist/remote/guides,
# light `<name>.png` and dark `<name>-dark.png`) into website/guides/images.
# Updating every guide picture: `remote guides`, then this.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT_DIR/dist/remote/guides"
TARGET="$ROOT_DIR/website/guides/images"

shopt -s nullglob
pictures=("$SOURCE"/*.png)
if (( ${#pictures[@]} == 0 )); then
  echo "No pictures in dist/remote/guides: run ./script/build_and_run.sh remote guides first." >&2
  exit 1
fi
mkdir -p "$TARGET"
cp "${pictures[@]}" "$TARGET/"
echo "${#pictures[@]} pictures copied to website/guides/images."
