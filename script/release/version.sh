#!/usr/bin/env bash
# The version of a release, from the releases themselves: the newest
# release tag (v<version>-<build>) raised by one patch or one minor, or the
# floor when that is higher. The floor is MARKETING_VERSION (Xcode's, while
# it builds), else project.yml's: raise it there only to jump (1.0.0).
# `current`: the version a build of this checkout says (no raise).
# docs/github-workflow-runs.md, "The release workflow's version".
#
#   script/release/version.sh patch|minor|current
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

bump="${1:-}"
[[ "$bump" == patch || "$bump" == minor || "$bump" == current ]] || {
  echo "Usage: script/release/version.sh patch|minor|current" >&2
  exit 2
}
semver='^[0-9]+\.[0-9]+\.[0-9]+$'
floor="${MARKETING_VERSION:-$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([0-9.]*\)"\{0,1\} *$/\1/p' "$ROOT_DIR/project.yml" | head -n 1)}"
[[ "$floor" =~ $semver ]] || { echo "No MARKETING_VERSION x.y.z in project.yml." >&2; exit 2; }

# The higher of two versions, number by number.
higher() { printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1; }

latest=""
while IFS= read -r tag; do
  # Only a release's own tag, v<version>-<build>: never a v0.5.0-rc.1. A
  # draft (a failed upload, run again) has no tag until it is published,
  # so its retry takes the same version and finds it.
  [[ "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)-[0-9]+$ ]] || continue
  version="${BASH_REMATCH[1]}"
  latest="$(higher "${latest:-$version}" "$version")"
done < <(git -C "$ROOT_DIR" tag --list 'v[0-9]*' 2>/dev/null)

if [[ -z "$latest" ]]; then
  echo "$floor"
  exit 0
fi
IFS=. read -r major minor patch <<< "$latest"
case "$bump" in
  patch) next="$major.$minor.$((patch + 1))" ;;
  minor) next="$major.$((minor + 1)).0" ;;
  current) next="$latest" ;;
esac
higher "$next" "$floor"
