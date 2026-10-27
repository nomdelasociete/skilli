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
# Only a whole, green `remote guides` run: a failed one leaves some pictures
# behind, and copying them would mix two runs (light from one, dark from another).
python3 - "$ROOT_DIR/dist/remote/selftest.json" "$SOURCE" <<'PY'
import json, pathlib, sys
report, source = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
if not report.is_file():
    sys.exit('No dist/remote/selftest.json: run ./script/build_and_run.sh remote guides first.')
run = json.loads(report.read_text())
guides = [c for c in run['checks'] if c['name'].startswith('Guide picture: ')]
if run['failed'] or not guides:
    sys.exit(f"The last remote run is not a green `remote guides` ({run['failed']} failed, {len(guides)} guide pictures): nothing copied.")
missing = [f"{c['name'].removeprefix('Guide picture: ')}{suffix}.png" for c in guides for suffix in ('', '-dark')
           if not (source / f"{c['name'].removeprefix('Guide picture: ')}{suffix}.png").is_file()]
if missing:
    sys.exit('Missing from dist/remote/guides: ' + ', '.join(missing) + ': nothing copied.')
PY
mkdir -p "$TARGET"
# The run's pictures replace them all (a surface the scope no longer captures
# goes), and only once every copy is made: a failed copy leaves the old set.
staging="$(mktemp -d "$ROOT_DIR/dist/guide-images.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
cp "${pictures[@]}" "$staging/"
rm -f "$TARGET"/*.png
mv "$staging"/*.png "$TARGET/"
echo "${#pictures[@]} pictures copied to website/guides/images."
